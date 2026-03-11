#pragma once
#include <string>

// Start the embedded HTTP GUI server.
// Opens http://127.0.0.1:18080 in the default browser, then blocks until killed.
// bundled_url: optional VLESS/VMess/SS URL to pre-fill in the form.
void run_gui(const std::string& bundled_url = "");
