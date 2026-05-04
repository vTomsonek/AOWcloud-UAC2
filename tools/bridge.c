/*
 * Real-time ALSA PCM bridge using tinyalsa - v6.0.0
 * Forwards audio from one PCM capture device to another playback device,
 * or pipes PCM through stdin/stdout for in-process plumbing.
 * Plus: --pcm-to-mp3 mode dla MP3 substitution (Plan O).
 *
 * v6.0.0 changes:
 *   - Added --pcm-to-mp3 mode (Bridge encodes voice DL → MP3 via external lame)
 *
 * v3.0.6 changes vs proposed:
 *   - XRUN recovery via pcm_prepare() in stdin mode (was: break)
 *   - Better error logging (rc + errno + strerror)
 *   - Separate start_threshold for PCM_OUT (was: 0 -> immediate XRUN)
 *
 * Usage:
 *   bridge <src_card> <src_dev> <dst_card> <dst_dev>   classic capture -> playback
 *   bridge --stdin  <dst_card> <dst_dev>                stdin (PCM) -> playback
 *   bridge --stdout <src_card> <src_dev>                capture -> stdout (PCM)
 *   bridge --pcm-to-mp3 <input.pcm> <output.mp3>        encode raw PCM (48kHz mono S16_LE)
 *                                                       to MP3 32kbps mono via /system/xbin/lame
 *
 * Format for audio modes: 48000 Hz, 2 ch, S16_LE, period 1024 frames, 4 periods.
 * Format for --pcm-to-mp3: input must be 48kHz mono S16_LE raw PCM.
 */

#include <sys/wait.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <tinyalsa/asoundlib.h>

#define BUFFER_FRAMES 1024
#define CHANNELS 2
#define RATE 48000
#define PERIOD_COUNT 4

static volatile int running = 1;

void sig_handler(int sig) {
    (void)sig;
    running = 0;
}

/* config for PCM_IN (capture) */
static void make_config_in(struct pcm_config *config) {
    memset(config, 0, sizeof(*config));
    config->channels = CHANNELS;
    config->rate = RATE;
    config->format = PCM_FORMAT_S16_LE;
    config->period_size = BUFFER_FRAMES;
    config->period_count = PERIOD_COUNT;
    config->start_threshold = 0;
    config->stop_threshold = 0;
    config->silence_threshold = 0;
}

/* config for PCM_OUT (playback) - need real thresholds, otherwise XRUN at t~=0 */
static void make_config_out(struct pcm_config *config) {
    memset(config, 0, sizeof(*config));
    config->channels = CHANNELS;
    config->rate = RATE;
    config->format = PCM_FORMAT_S16_LE;
    config->period_size = BUFFER_FRAMES;
    config->period_count = PERIOD_COUNT;
    /* don't auto-start until 1 period is buffered */
    config->start_threshold = BUFFER_FRAMES;
    /* stop at full buffer = period_size * period_count */
    config->stop_threshold = BUFFER_FRAMES * PERIOD_COUNT;
    config->silence_threshold = 0;
    config->silence_size = 0;
    config->avail_min = BUFFER_FRAMES;
}

/* ===== Classic mode: capture -> playback ===== */
static int run_loopback(int src_card, int src_dev, int dst_card, int dst_dev) {
    struct pcm_config cfg_in, cfg_out;
    make_config_in(&cfg_in);
    make_config_out(&cfg_out);

    fprintf(stderr, "[bridge] Opening capture: card %d dev %d\n", src_card, src_dev);
    struct pcm *cap = pcm_open(src_card, src_dev, PCM_IN, &cfg_in);
    if (!cap || !pcm_is_ready(cap)) {
        fprintf(stderr, "[bridge] Failed to open capture: %s\n", pcm_get_error(cap));
        return 1;
    }

    fprintf(stderr, "[bridge] Opening playback: card %d dev %d\n", dst_card, dst_dev);
    struct pcm *play = pcm_open(dst_card, dst_dev, PCM_OUT, &cfg_out);
    if (!play || !pcm_is_ready(play)) {
        fprintf(stderr, "[bridge] Failed to open playback: %s\n", pcm_get_error(play));
        pcm_close(cap);
        return 1;
    }

    int frame_bytes = pcm_frames_to_bytes(cap, BUFFER_FRAMES);
    char *buffer = malloc(frame_bytes);
    if (!buffer) {
        fprintf(stderr, "[bridge] Failed to allocate buffer\n");
        pcm_close(cap);
        pcm_close(play);
        return 1;
    }

    fprintf(stderr, "[bridge] Running. Format: %d Hz, %d ch, S16_LE, period %d frames\n",
            RATE, CHANNELS, BUFFER_FRAMES);
    fprintf(stderr, "[bridge] Press Ctrl+C to stop.\n");

    long total_frames = 0;
    int xrun_recoveries = 0;
    while (running) {
        int rc = pcm_read(cap, buffer, frame_bytes);
        if (rc < 0) {
            int e = errno;
            fprintf(stderr, "[bridge] pcm_read: rc=%d errno=%d (%s) alsa='%s'\n",
                    rc, e, strerror(e), pcm_get_error(cap));
            if (rc == -EPIPE || e == EPIPE) {
                if (pcm_prepare(cap) < 0) {
                    fprintf(stderr, "[bridge] pcm_prepare(cap) failed: %s\n", pcm_get_error(cap));
                    break;
                }
                xrun_recoveries++;
                continue;
            }
            break;
        }
        rc = pcm_write(play, buffer, frame_bytes);
        if (rc < 0) {
            int e = errno;
            fprintf(stderr, "[bridge] pcm_write: rc=%d errno=%d (%s) alsa='%s'\n",
                    rc, e, strerror(e), pcm_get_error(play));
            if (rc == -EPIPE || e == EPIPE) {
                if (pcm_prepare(play) < 0) {
                    fprintf(stderr, "[bridge] pcm_prepare(play) failed: %s\n", pcm_get_error(play));
                    break;
                }
                xrun_recoveries++;
                continue;
            }
            break;
        }
        total_frames += BUFFER_FRAMES;
    }

    fprintf(stderr, "\n[bridge] Stopped. Total: %ld frames (%.2f sec), xrun_recoveries=%d\n",
            total_frames, (double)total_frames / RATE, xrun_recoveries);

    free(buffer);
    pcm_close(cap);
    pcm_close(play);
    return 0;
}

/* ===== --stdin mode: stdin (PCM bytes) -> ALSA playback ===== */
static int run_stdin_mode(int dst_card, int dst_dev) {
    struct pcm_config cfg;
    make_config_out(&cfg);

    fprintf(stderr, "[bridge --stdin] Opening playback: card %d dev %d\n", dst_card, dst_dev);
    struct pcm *play = pcm_open(dst_card, dst_dev, PCM_OUT, &cfg);
    if (!play || !pcm_is_ready(play)) {
        fprintf(stderr, "[bridge --stdin] Failed to open playback: %s\n", pcm_get_error(play));
        return 1;
    }

    int frame_bytes = pcm_frames_to_bytes(play, BUFFER_FRAMES);
    char *buffer = malloc(frame_bytes);
    if (!buffer) {
        fprintf(stderr, "[bridge --stdin] Failed to allocate buffer\n");
        pcm_close(play);
        return 1;
    }

    fprintf(stderr, "[bridge --stdin] Running. stdin -> card %d dev %d (%d Hz, %d ch, S16_LE, period %d frames, %d periods)\n",
            dst_card, dst_dev, RATE, CHANNELS, BUFFER_FRAMES, PERIOD_COUNT);

    long total_frames = 0;
    int xrun_recoveries = 0;
    while (running) {
        /* gather a full period from stdin */
        size_t got = 0;
        int eof = 0;
        while (got < (size_t)frame_bytes && running) {
            size_t n = fread(buffer + got, 1, (size_t)frame_bytes - got, stdin);
            if (n == 0) {
                if (feof(stdin)) { eof = 1; break; }
                if (ferror(stdin)) {
                    fprintf(stderr, "[bridge --stdin] stdin read error: %s\n", strerror(errno));
                    goto out;
                }
            }
            got += n;
        }
        if (got == 0 && eof) break;
        if (got < (size_t)frame_bytes) {
            memset(buffer + got, 0, (size_t)frame_bytes - got);
        }

        int rc = pcm_write(play, buffer, frame_bytes);
        if (rc < 0) {
            int e = errno;
            fprintf(stderr, "[bridge --stdin] pcm_write: rc=%d errno=%d (%s) alsa='%s'\n",
                    rc, e, strerror(e), pcm_get_error(play));
            if (rc == -EPIPE || e == EPIPE) {
                fprintf(stderr, "[bridge --stdin] XRUN -> pcm_prepare\n");
                if (pcm_prepare(play) < 0) {
                    fprintf(stderr, "[bridge --stdin] pcm_prepare failed: %s\n", pcm_get_error(play));
                    break;
                }
                xrun_recoveries++;
                /* re-write same period after recovery, otherwise we drop ~21ms */
                rc = pcm_write(play, buffer, frame_bytes);
                if (rc < 0) {
                    fprintf(stderr, "[bridge --stdin] pcm_write after prepare failed: rc=%d errno=%d (%s) alsa='%s'\n",
                            rc, errno, strerror(errno), pcm_get_error(play));
                    /* don't break; let the next iteration try again */
                    continue;
                }
            } else {
                break;
            }
        }
        total_frames += BUFFER_FRAMES;
        if (eof) break;
    }
out:
    fprintf(stderr, "\n[bridge --stdin] Stopped. Total: %ld frames (%.2f sec), xrun_recoveries=%d\n",
            total_frames, (double)total_frames / RATE, xrun_recoveries);

    free(buffer);
    pcm_close(play);
    return 0;
}

/* ===== --stdout mode: ALSA capture -> stdout (PCM bytes) ===== */
static int run_stdout_mode(int src_card, int src_dev) {
    struct pcm_config cfg;
    make_config_in(&cfg);

    fprintf(stderr, "[bridge --stdout] Opening capture: card %d dev %d\n", src_card, src_dev);
    struct pcm *cap = pcm_open(src_card, src_dev, PCM_IN, &cfg);
    if (!cap || !pcm_is_ready(cap)) {
        fprintf(stderr, "[bridge --stdout] Failed to open capture: %s\n", pcm_get_error(cap));
        return 1;
    }

    int frame_bytes = pcm_frames_to_bytes(cap, BUFFER_FRAMES);
    char *buffer = malloc(frame_bytes);
    if (!buffer) {
        fprintf(stderr, "[bridge --stdout] Failed to allocate buffer\n");
        pcm_close(cap);
        return 1;
    }

    setvbuf(stdout, NULL, _IONBF, 0);

    fprintf(stderr, "[bridge --stdout] Running. card %d dev %d -> stdout (%d Hz, %d ch, S16_LE)\n",
            src_card, src_dev, RATE, CHANNELS);

    long total_frames = 0;
    int xrun_recoveries = 0;
    while (running) {
        int rc = pcm_read(cap, buffer, frame_bytes);
        if (rc < 0) {
            int e = errno;
            fprintf(stderr, "[bridge --stdout] pcm_read: rc=%d errno=%d (%s) alsa='%s'\n",
                    rc, e, strerror(e), pcm_get_error(cap));
            if (rc == -EPIPE || e == EPIPE) {
                if (pcm_prepare(cap) < 0) {
                    fprintf(stderr, "[bridge --stdout] pcm_prepare failed: %s\n", pcm_get_error(cap));
                    break;
                }
                xrun_recoveries++;
                continue;
            }
            break;
        }
        size_t written = 0;
        while (written < (size_t)frame_bytes) {
            size_t n = fwrite(buffer + written, 1, (size_t)frame_bytes - written, stdout);
            if (n == 0) {
                fprintf(stderr, "[bridge --stdout] stdout write error: %s\n", strerror(errno));
                goto out;
            }
            written += n;
        }
        fflush(stdout);
        total_frames += BUFFER_FRAMES;
    }
out:
    fprintf(stderr, "\n[bridge --stdout] Stopped. Total: %ld frames (%.2f sec), xrun_recoveries=%d\n",
            total_frames, (double)total_frames / RATE, xrun_recoveries);

    free(buffer);
    pcm_close(cap);
    return 0;
}

/* ===== --pcm-to-mp3 mode: raw PCM 48kHz mono S16_LE -> MP3 via lame =====
 * Wymaga /system/xbin/lame binary (dolaczone do KSU module).
 * Mi soundrecorder format: MP3 48kHz mono 32kbps CBR -> matching flags.
 */
static int run_pcm_to_mp3(const char *input_pcm, const char *output_mp3) {
    /* sprawdz czy input istnieje */
    FILE *f = fopen(input_pcm, "rb");
    if (!f) {
        fprintf(stderr, "[bridge --pcm-to-mp3] Cannot open input: %s (errno=%d %s)\n",
                input_pcm, errno, strerror(errno));
        return 1;
    }
    fseek(f, 0, SEEK_END);
    long input_size = ftell(f);
    fclose(f);
    if (input_size <= 0) {
        fprintf(stderr, "[bridge --pcm-to-mp3] Input file empty: %s\n", input_pcm);
        return 1;
    }
    fprintf(stderr, "[bridge --pcm-to-mp3] Input PCM size: %ld bytes (~%.1f sec)\n",
            input_size, (double)input_size / (48000 * 2));

    /* fork + exec lame */
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "[bridge --pcm-to-mp3] fork failed: %s\n", strerror(errno));
        return 1;
    }
    if (pid == 0) {
        /* child: execve lame
         * lame -r --signed -s 48 --bitwidth 16 -m m -b 32 --cbr input.pcm output.mp3
         *   -r              : raw PCM input
         *   --signed        : signed samples
         *   -s 48           : 48 kHz sample rate
         *   --bitwidth 16   : 16-bit samples
         *   -m m            : mono mode
         *   -b 32           : 32 kbps bitrate (matches Mi soundrecorder)
         *   --cbr           : constant bit rate
         */
        char *args[] = {
            "/system/xbin/lame",
            "-r",
            "--signed",
            "-s", "48",
            "--bitwidth", "16",
            "-m", "m",
            "-b", "32",
            "--cbr",
            (char*)input_pcm,
            (char*)output_mp3,
            NULL
        };
        execv(args[0], args);
        /* exec failed */
        fprintf(stderr, "[bridge --pcm-to-mp3 child] execv lame failed: %s\n", strerror(errno));
        _exit(127);
    }

    /* parent: wait for lame */
    int status;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "[bridge --pcm-to-mp3] waitpid failed: %s\n", strerror(errno));
        return 1;
    }
    if (!WIFEXITED(status)) {
        fprintf(stderr, "[bridge --pcm-to-mp3] lame did not exit normally\n");
        return 1;
    }
    int rc = WEXITSTATUS(status);
    if (rc != 0) {
        fprintf(stderr, "[bridge --pcm-to-mp3] lame exit code: %d\n", rc);
        return rc;
    }

    /* verify output */
    f = fopen(output_mp3, "rb");
    if (!f) {
        fprintf(stderr, "[bridge --pcm-to-mp3] Output MP3 not created: %s\n", output_mp3);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    long output_size = ftell(f);
    fclose(f);
    fprintf(stderr, "[bridge --pcm-to-mp3] Encoded OK: %s (%ld bytes)\n", output_mp3, output_size);
    return 0;
}

/* ===== main: dispatcher ===== */
int main(int argc, char **argv) {
    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);
    signal(SIGPIPE, sig_handler);

    if (argc == 4 && strcmp(argv[1], "--stdin") == 0) {
        return run_stdin_mode(atoi(argv[2]), atoi(argv[3]));
    }
    if (argc == 4 && strcmp(argv[1], "--stdout") == 0) {
        return run_stdout_mode(atoi(argv[2]), atoi(argv[3]));
    }
    if (argc == 4 && strcmp(argv[1], "--pcm-to-mp3") == 0) {
        return run_pcm_to_mp3(argv[2], argv[3]);
    }
    if (argc == 5) {
        return run_loopback(atoi(argv[1]), atoi(argv[2]),
                            atoi(argv[3]), atoi(argv[4]));
    }

    fprintf(stderr, "Usage: %s <src_card> <src_dev> <dst_card> <dst_dev>\n", argv[0]);
    fprintf(stderr, "       %s --stdin  <dst_card> <dst_dev>     (stdin PCM -> playback)\n", argv[0]);
    fprintf(stderr, "       %s --stdout <src_card> <src_dev>     (capture -> stdout PCM)\n", argv[0]);
    fprintf(stderr, "       %s --pcm-to-mp3 <input.pcm> <output.mp3>  (encode 48kHz mono PCM -> MP3 via lame)\n", argv[0]);
    fprintf(stderr, "Example: %s 0 1 2 0   (Loopback capture -> UAC2 playback)\n", argv[0]);
    return 1;
}
