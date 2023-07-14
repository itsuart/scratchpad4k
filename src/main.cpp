#include <Windows.h>
#include <shellscalingapi.h>
#include "./window_msg_dispatcher.h"
#include "./main_window.h"

#include <vector>
#include <cassert>

int APIENTRY wWinMain(HINSTANCE hInstance, HINSTANCE, LPWSTR /*lpCmdLine*/, int /*nCmdShow*/){

    ::SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);

    using namespace w;
    WindowMsgDispatcher dispatcher{};
    MainWindow mainWnd(dispatcher, hInstance);

    MSG msg;
    while (GetMessage(&msg, nullptr, 0, 0)) {
        if (mainWnd.preview_message(msg)) {
            continue;
        }

        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return (int)msg.wParam;
}