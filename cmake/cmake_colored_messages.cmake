if(NOT WIN32)
    string(ASCII 27 ESC)
    # Define color codes
    set(RESET        "${ESC}[0m")
    set(RED          "${ESC}[31m")
    set(GREEN        "${ESC}[32m")
    set(YELLOW       "${ESC}[33m")
    set(BLUE         "${ESC}[34m")

    # Additional colors
    set(MAGENTA      "${ESC}[35m")
    set(CYAN         "${ESC}[36m")

    # Bright colors (may not be supported in all terminals)
    set(BRIGHT_RED       "${ESC}[91m")
    set(BRIGHT_GREEN     "${ESC}[92m")
    set(BRIGHT_YELLOW    "${ESC}[93m")
    set(BRIGHT_BLUE      "${ESC}[94m")
    set(BRIGHT_MAGENTA   "${ESC}[95m")
    set(BRIGHT_CYAN      "${ESC}[96m")

    # Text styles
    set(BOLD         "${ESC}[1m")
    set(UNDERLINE    "${ESC}[4m")

    # Background colors
    set(BG_RED       "${ESC}[41m")
    set(BG_GREEN     "${ESC}[42m")
    set(BG_YELLOW    "${ESC}[43m")
    set(BG_BLUE      "${ESC}[44m")
endif()
