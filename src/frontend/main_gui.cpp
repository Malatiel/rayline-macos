// Standalone entry point for the veil-gui binary.
// All GUI logic lives in gui_server.cpp / gui_server.hpp.
#include "gui_server.hpp"

int main(int argc, char* argv[]) {
    run_gui(argc >= 2 ? argv[1] : "");
    return 0;
}
