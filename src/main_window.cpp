#include "./main_window.h"
#include <stdexcept>
#include <cassert>
#include <algorithm>
#include <unordered_set>
#include <format>

#include "helpers/string_conversions.h"
#include "helpers/error_message.h"

namespace {

    template<typename T>
    class defer {
    public:
        explicit defer(T&& cb): _cb(std::forward<T>(cb)){}
        defer(const defer&) = delete;
        defer(defer&&) = delete;

        ~defer() {
            _cb();
        }
    private:
        T&& _cb;
    };

    constexpr std::uint32_t DEFAULT_NON_SCALED_DPI = 96;

    bool is_button_down(int virtualKey){
        constexpr int BTN_DOWN = 0x8000;
        return BTN_DOWN == (::GetKeyState (virtualKey) & BTN_DOWN);
    }


    void get_window_text(HWND hEdit, std::wstring& result) {
        const LRESULT lengthWithoutNull = ::SendMessageW(hEdit, WM_GETTEXTLENGTH, 0, 0);
        if (lengthWithoutNull == 0) {
            result.resize(0);
            return;
        }

        result.resize(lengthWithoutNull + 1);
        const LRESULT charactersCopied = ::SendMessageW(hEdit, WM_GETTEXT, result.size(), (LPARAM)&result[0]);
        result.resize(charactersCopied);
    }

    std::wstring get_window_text(HWND hEdit) {
        std::wstring result;

        get_window_text(hEdit, result);
        return result;
    }


    struct Rect : RECT {
        LONG get_width() const noexcept {
            return right - left;
        }

        LONG get_height() const noexcept {
            return bottom - top;
        }
    };

    void center_window(HWND hCreatedUnownedTopWindow) {
        RECT windowRect;
        if (::GetWindowRect(hCreatedUnownedTopWindow, &windowRect)) {
            if (const HMONITOR hMonitor = ::MonitorFromWindow(hCreatedUnownedTopWindow, MONITOR_DEFAULTTONULL)) {
                MONITORINFO mi;
                mi.cbSize = sizeof(mi);
                if (::GetMonitorInfoW(hMonitor, &mi)) {
                    const auto absMonitorWidth = abs(mi.rcWork.right - mi.rcWork.left);
                    const auto absWindowWidth = abs(windowRect.right - windowRect.left);
                    const auto middleX = (absMonitorWidth - absWindowWidth) / 2;
                    if (middleX > 0) {
                        //meaning window's width < than width of the monitor
                        windowRect.left = mi.rcWork.left + middleX;
                    }

                    const auto absMonitorHeight = abs(mi.rcWork.bottom - mi.rcWork.top);
                    const auto absWindowHeight = abs(windowRect.bottom - windowRect.top);
                    const auto middleY = (absMonitorHeight - absWindowHeight) / 2;
                    if (middleY > 0) {
                        //meaning window's height < height of the monitor
                        windowRect.top = mi.rcWork.top + middleY;
                    }

                    //this however does not solve my original problem with Emacs
                    //(because it sets its size much later after creation of the window)
                    ::SetWindowPos(
                        hCreatedUnownedTopWindow, NULL,
                        windowRect.left, windowRect.top, 0, 0,
                        SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOSIZE
                    );
                }
            }
        }
    }

    template<typename T>
    std::vector<std::basic_string<T>> split(const std::basic_string<T>& input, T separator, bool ignoreEmptyParts = false) {
        using string = std::basic_string<T>;
        std::vector<string> result;

        string buffer;
        for (T current : input) {
            if (current == separator) {
                if (ignoreEmptyParts and buffer.empty()) {
                    continue;
                }
                result.push_back(buffer);
                buffer.clear();
            } else {
                buffer.push_back(std::move(current));
            }
        }

        if (ignoreEmptyParts and buffer.empty()) {
            // do nothing
        }
        else {
            result.push_back(buffer);
        }
        return result;
    }

    std::string read_file_fully(HANDLE handle) {
        static char BUFFER[4 * 1024];

        std::string result;
        DWORD dwBytesRead;
        while (::ReadFile(handle, &BUFFER[0], sizeof BUFFER, &dwBytesRead, nullptr)) {
            result.append(&BUFFER[0], dwBytesRead);
            if (dwBytesRead == 0) {
                break;
            }
        }

        return result;
    }

    BOOL write_to_file(HANDLE handle, const void* data, std::size_t sizeOfData) {
        DWORD dwBytesWritten;
        return ::WriteFile(handle, data, sizeOfData, &dwBytesWritten, nullptr);
    }

    constexpr wchar_t APP_NAME[] = L"Scratchpad4k";
    constexpr wchar_t APP_NAME_EMPTY[] = L"Scratchpad4k (empty)";

} // namespace

namespace w {

    MainWindow::MainWindow(WindowMsgDispatcher& dispatcher, HINSTANCE hInstance)
    : _hInstance(hInstance)
    , _mainWnd(nullptr)
    , _contentEditWnd(nullptr)
    , _dpi(::GetDpiForSystem())
    {
        const static wchar_t* WND_CLASS_NAME = L"scratchpad4k-main";

        {
            WNDCLASSEXW wcex;

            wcex.cbSize = sizeof(WNDCLASSEX);

            wcex.style = CS_HREDRAW | CS_VREDRAW;
            wcex.lpfnWndProc = dispatcher.DispatchingProc;
            wcex.cbClsExtra = 0;
            wcex.cbWndExtra = 0;
            wcex.hInstance = _hInstance;
            wcex.hIcon = nullptr;
            wcex.hCursor = LoadCursor(nullptr, IDC_ARROW);
            wcex.hbrBackground = (HBRUSH)(COLOR_WINDOW);
            wcex.lpszMenuName = nullptr;
            wcex.lpszClassName = WND_CLASS_NAME;
            wcex.hIconSm = nullptr;

            ::RegisterClassExW(&wcex);
        }

        dispatcher.bind_to_next_new_window(*this);

        _mainWnd = CreateWindowW(
            WND_CLASS_NAME,
            APP_NAME,
            WS_OVERLAPPEDWINDOW,
            0, 0,
            to_dpi_aware_pixels(300), to_dpi_aware_pixels(300),
            nullptr,
            nullptr,
            _hInstance,
            nullptr
        );

        if (! _mainWnd) {
            throw std::runtime_error("failed to create main window");
        }

        center_window(_mainWnd);

        create_subcontrols();

        layout_subcontrols();

        ::ShowWindow(_mainWnd, SW_SHOW);

        ::UpdateWindow(_mainWnd);
    }

    void MainWindow::create_subcontrols() {
        _contentEditWnd =
            ::CreateWindowW(
                L"edit",
                nullptr,
                WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_EX_CLIENTEDGE | ES_MULTILINE,
                0, 0,
                to_dpi_aware_pixels(100), to_dpi_aware_pixels(200),
                _mainWnd,
                nullptr,
                _hInstance,
                nullptr
            );
        assert(_contentEditWnd);

        {
            NONCLIENTMETRICSW metrics;
            metrics.cbSize = sizeof(metrics);

            {
                const bool getMetrics = ::SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, metrics.cbSize, &metrics, 0, _dpi);
                assert(getMetrics);
            }

            //For some fucking reason, for fonts 72 ppi is the default.
            metrics.lfMenuFont.lfHeight = 16 * _dpi / 72;
            HFONT hFont = ::CreateFontIndirectW(&metrics.lfMenuFont);
            assert(hFont);

            ::SendMessageW(_contentEditWnd, WM_SETFONT, (WPARAM)hFont, false);
        }

    }

    void MainWindow::layout_subcontrols() {
        constexpr int LEFT_PADDING = 0;
        constexpr int RIGHT_PADDING = 0;
        constexpr int TOP_PADDING = 0;
        constexpr int BOTTOM_PADDING = 0;

        RECT clientRect;
        if (not ::GetClientRect(_mainWnd, &clientRect)) {
            return;
        }

        ::MoveWindow(
            _contentEditWnd,
            LEFT_PADDING,
            TOP_PADDING,
            clientRect.right - (LEFT_PADDING + RIGHT_PADDING),
            clientRect.bottom - clientRect.top - (TOP_PADDING + BOTTOM_PADDING),
            false
        );

    }

    void MainWindow::on_save_content_command() noexcept {
        std::wstring buffer{};
        buffer.resize(33 * 1024); // TODO: use preperly calculated max size

        OPENFILENAMEW saveFileDialogSettings{ 0 };
        saveFileDialogSettings.lStructSize = sizeof(OPENFILENAMEW);
        saveFileDialogSettings.hwndOwner = _mainWnd;
        saveFileDialogSettings.lpstrFile = buffer.data();
        saveFileDialogSettings.nMaxFile = buffer.size();
        saveFileDialogSettings.Flags = OFN_DONTADDTORECENT | OFN_FORCESHOWHIDDEN | OFN_LONGNAMES | OFN_NOTESTFILECREATE;

        if (not ::GetSaveFileNameW(&saveFileDialogSettings)) {

            const DWORD err = CommDlgExtendedError();
            if (const bool isCancelled = (err == 0); isCancelled) {
                return;
            }

            const std::wstring errorMessage = std::format(L"Extended error code : {}.", err);
            ::MessageBoxW(_mainWnd, errorMessage.c_str(), L"::GetSaveFileNameW() failed", MB_OK | MB_ICONERROR);
            return;
        }

        //resize the file name buffer to exact content size
        for (std::size_t i = saveFileDialogSettings.nFileOffset; i < buffer.size(); ++i) {
            if (buffer[i] == 0) {
                buffer.resize(i);
                break;
            }
        }

        if (buffer.size() >= MAX_PATH) {
            buffer.insert(0, L"\\\\?\\");
        }

        HANDLE hFile = ::CreateFileW(
            buffer.c_str(),
            GENERIC_WRITE,
            FILE_SHARE_READ,
            nullptr,
            CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr
        );
        if (hFile == INVALID_HANDLE_VALUE) {
            const DWORD lastError = ::GetLastError();
            const auto errorDescription = helpers::get_error_message_w(lastError);
            const std::wstring errorMessage = std::format(L"{}(error code = {})", errorDescription.get(), lastError);
            return;
        }

        defer autoCloseFile{
            [&hFile]() {
                ::CloseHandle(hFile);
                hFile = nullptr;
            }
        };

        const std::string contentInUtf8Encoding = helpers::to_string(get_window_text(_contentEditWnd));

        if (not write_to_file(hFile, contentInUtf8Encoding.data(), contentInUtf8Encoding.size())) {
            const DWORD lastError = ::GetLastError();
            const auto errorDescription = helpers::get_error_message_w(lastError);
            const std::wstring errorMessage = std::format(L"{}(error code = {})", errorDescription.get(), lastError);
            return;
        }


    }

    void MainWindow::on_content_changed() noexcept{
        std::wstring content = get_window_text(_contentEditWnd);

        //TODO: append "({} wchars)" or "(empty)" ?
        //TODO: also optimize, to many copying back and forth.
        if (content.empty()) {
            ::SetWindowTextW(_mainWnd, APP_NAME_EMPTY);
            return;
        }

        const std::size_t contentSize = content.size();
        {
            std:size_t offset{ 0 };
            for (wchar_t c : content) {
                if (c == L'\n' or c == L'\r') {
                    content.erase(offset);
                    break;
                }
                ++offset;
            }
        
        }

        content.append(std::format(L" -- {} ({} wchars)", APP_NAME, contentSize));
        ::SetWindowTextW(_mainWnd, content.c_str());
    }

    void MainWindow::on_dpi_changed(std::uint32_t newDPI, const RECT* suggestedNewRect) noexcept{
        _dpi = newDPI;

        const Rect& rect{ *suggestedNewRect };
        ::SetWindowPos(_mainWnd, nullptr, rect.left, rect.top, rect.get_width(), rect.get_height(), SWP_NOZORDER | SWP_NOACTIVATE);
    }

    std::uint32_t MainWindow::to_dpi_aware_pixels(std::uint32_t defaultDPIPixels) const noexcept{
        return static_cast<std::uint32_t>(static_cast<std::uint64_t>(defaultDPIPixels) * _dpi / DEFAULT_NON_SCALED_DPI);
    }

    LRESULT MainWindow::process_message(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) noexcept {
        constexpr LRESULT MESSAGE_PROCESSED = 0;

        switch (message) {
            case WM_CLOSE: {
                ::PostQuitMessage(0);
                return MESSAGE_PROCESSED;
            } break;

            case WM_SIZING: {
                Rect& r = *(Rect*)lParam;
                const long effectiveWidth = (std::max)(r.get_width(), (LONG)to_dpi_aware_pixels(200));
                const long effectiveHeight = (std::max)(r.get_height(), (LONG)to_dpi_aware_pixels(100));
                r.bottom = r.top + effectiveHeight;
                r.right = r.left + effectiveWidth;
                return true;
            } break;

            case WM_SIZE: {
                //const int newWidth = LOWORD(lParam);
                //const int newHeight = LOWORD(lParam);
                layout_subcontrols();
                return MESSAGE_PROCESSED;
            } break;

            case WM_ACTIVATE: {
                if (LOWORD(wParam) != WA_INACTIVE) {
                    ::SetFocus(_contentEditWnd);
                    return MESSAGE_PROCESSED;
                }
            } break;

            case WM_DPICHANGED: {
                const std::uint32_t newDPI = LOWORD(wParam);
                const RECT* suggestedNewRect = reinterpret_cast<const RECT*>(lParam);
                on_dpi_changed(newDPI, suggestedNewRect);
                return MESSAGE_PROCESSED;
            } break;

            case WM_COMMAND: {
                if (lParam == (LPARAM)_contentEditWnd) {
                    const auto notificationCode = HIWORD(wParam);
                    if (notificationCode == EN_UPDATE) {
                        on_content_changed();
                        return MESSAGE_PROCESSED;
                    }
                }
            } break;

        } //switch

        return DefWindowProcW(hWnd, message, wParam, lParam);
    }

    // returns true if message was handled and therefore need not be dispatched
    bool MainWindow::preview_message(const MSG& msg) {
        const auto message = msg.message;
        const auto wParam = msg.wParam;
        const auto lParam = msg.lParam;

        if (const bool isOneOfMyWindows = (msg.hwnd == _mainWnd or msg.hwnd == _contentEditWnd); not isOneOfMyWindows) {
            return false; // not my window, don't care.
        }

        //intercept all C+ENTER
        if (message != WM_KEYUP and message != WM_KEYDOWN) {
            return false;
        }

        if (wParam == VK_ESCAPE and message == WM_KEYDOWN) {
            ::PostQuitMessage(0);
            return true;
        }

        if (is_button_down(VK_CONTROL)){
            if (wParam == 'S') {
                if (message == WM_KEYUP) {
                    on_save_content_command();
                    return true;
                }
                else { // WM_KEYDOWN
                    return true;
                }
            }
            else if (wParam == 'A') {
                if (message == WM_KEYUP) {
                    ::PostMessageW(_contentEditWnd, EM_SETSEL, 0, -1);
                    return true;
                }
                else if (message == WM_KEYDOWN) {
                    return true;
                }
            }
        }
        return false;
    }
} //namespace
