#ifndef _EDITOR_H_
#define _EDITOR_H_

#include <stdint.h>
#include <stdbool.h>
#include "buffer.h"
#include "terminal.h"
#include "hbios.h"

#define EDITOR_VERSION     "0.3.0"
#define MAX_PATH_LEN       16

typedef struct {
    char filename[MAX_PATH_LEN];
    bool running;
    bool show_line_numbers;
    char status_msg[64];
} EditorApp;

extern EditorApp g_app;

void editor_init(const char *filename);
void editor_run(void);
bool editor_load_file(const char *filename);
bool editor_save_file(const char *filename);

#endif /* _EDITOR_H_ */
