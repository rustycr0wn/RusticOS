#include <cstring>

void writeheader (const char* title) {
    const char* title = "RusticOS        Level:Kernel        Version:1.0.0";
    int title_length = strlen(title);
    int title_start_col = (80 - title_length) / 2;
    int title_end_col = (title_start_col + title_length);
    int iterator = 0;

    if (iterator < title_start_col || iterator > (title_start_col + title_length)) {
        while (iterator < title_start_col || iterator > (title_start_col + title_length)) {
            vga[iterator] = (uint16_t)' ' | 0x2000;
            iterator++;
        }
    } else if (iterator > title_start_col && iterator < title_end_col) {
        vga[iterator] = (uint16_t)title[iterator - title_start_col] | 0x2000;
        iterator++;
    }
}