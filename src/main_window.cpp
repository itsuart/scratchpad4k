#include "./main_window.h"
#include <stdexcept>
#include <cassert>
#include <algorithm>
#include <cwctype>
#include <format>
#include <vector>

#include "helpers/string_conversions.h"
#include "helpers/error_message.h"

namespace {
    using namespace std::string_view_literals;

    struct Statistics final {
        std::uint64_t min;
        std::uint64_t max;
        std::uint64_t sum;
        std::uint64_t nNumbers;
        std::uint64_t average;
        std::uint64_t maxDeviation;

        [[nodiscard]]
        static Statistics from_string(std::wstring_view content) noexcept {
            struct Parser final {
                Statistics parse(std::wstring_view content) noexcept {
                    Statistics result{};
                    result.min = std::numeric_limits<decltype(min)>::max();

                    while (not content.empty()) {
                        content = skip_non_digits(content);

                        std::size_t digitCharsSkipped{0};

                        std::uint64_t currentNumber{0};
                        for (const wchar_t maybeDigitChar : content) {
                            if (std::iswdigit(maybeDigitChar)) {
                                currentNumber *= 10;
                                currentNumber += maybeDigitChar - L'0';
                                
                                digitCharsSkipped += 1;
                            }
                            else {
                                break;
                            }
                        }

                        if (digitCharsSkipped != 0) {
                            result.on_new_number(currentNumber);
                            content = content.substr(digitCharsSkipped);
                        }
                    }

                    
                    if (result.nNumbers >= 2) {
                        const std::uint64_t average = std::round( (double)result.sum / result.nNumbers);
                        result.average = average;
                        result.maxDeviation = std::max(result.max - average, average - result.min);
                    }

                    return result;
                }

                static std::wstring_view skip_non_digits(std::wstring_view content) noexcept {
                    std::size_t skipped{0};
                    for (const wchar_t c : content) {
                        if (std::iswdigit(c)) {
                            break;
                        }
                        skipped += 1;
                    }

                    return content.substr(skipped);
                }
            } parser;

            return parser.parse(content);
        }

        void to_string(std::wstring& buffer) const noexcept {
            if (nNumbers < 2) {
                buffer.assign(L"Not enough numbers detected (need at least 2).");
                return;
            }

            buffer.clear();
            std::format_to(std::back_inserter(buffer), L"Avg={} +-{}, Min={}, Max={}, Sum={}, nNumbers={}", average, maxDeviation, min, max, sum, nNumbers);
        }

    private:
        void on_new_number(std::uint64_t newNumber) noexcept {
            nNumbers += 1;
            min = std::min(min, newNumber);
            max = std::max(max, newNumber);
            sum += newNumber;
        }

    };

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

    BOOL write_to_file(HANDLE handle, const void* data, std::size_t sizeOfData) {
        DWORD dwBytesWritten;
        return ::WriteFile(handle, data, sizeOfData, &dwBytesWritten, nullptr);
    }

    constexpr wchar_t APP_NAME[] = L"Scratchpad4k";
    constexpr wchar_t APP_NAME_EMPTY[] = L"Scratchpad4k (empty)";

} // namespace

namespace w {

    MainWindow::MainWindow(WindowMsgDispatcher& dispatcher, HINSTANCE hInstance)
    : m_hInstance(hInstance)
    , m_mainWnd(nullptr)
    , m_contentEditWnd(nullptr)
    , m_dpi(::GetDpiForSystem())
    {
        const static wchar_t* WND_CLASS_NAME = L"scratchpad4k-main";

        {
            WNDCLASSEXW wcex;

            wcex.cbSize = sizeof(WNDCLASSEX);

            wcex.style = CS_HREDRAW | CS_VREDRAW;
            wcex.lpfnWndProc = dispatcher.DispatchingProc;
            wcex.cbClsExtra = 0;
            wcex.cbWndExtra = 0;
            wcex.hInstance = m_hInstance;
            wcex.hIcon = nullptr;
            wcex.hCursor = LoadCursor(nullptr, IDC_ARROW);
            wcex.hbrBackground = (HBRUSH)(COLOR_WINDOW);
            wcex.lpszMenuName = nullptr;
            wcex.lpszClassName = WND_CLASS_NAME;
            wcex.hIconSm = nullptr;

            ::RegisterClassExW(&wcex);
        }

        dispatcher.bind_to_next_new_window(*this);

        constexpr uint32_t INITIAL_WIDTH = 800;
        constexpr uint32_t INITIAL_HEIGHT = 600;

        m_mainWnd = CreateWindowW(
            WND_CLASS_NAME,
            APP_NAME,
            WS_OVERLAPPEDWINDOW,
            0, 0,
            to_dpi_aware_pixels(INITIAL_WIDTH), to_dpi_aware_pixels(INITIAL_HEIGHT),
            nullptr,
            nullptr,
            m_hInstance,
            nullptr
        );

        if (! m_mainWnd) {
            throw std::runtime_error("failed to create main window");
        }

        center_window(m_mainWnd);

        create_subcontrols();

        layout_subcontrols();

        ::ShowWindow(m_mainWnd, SW_SHOW);

        ::UpdateWindow(m_mainWnd);
    }

    void MainWindow::create_subcontrols() {
        m_contentEditWnd =
            ::CreateWindowW(
                L"edit",
                nullptr,
                WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_EX_CLIENTEDGE | ES_MULTILINE,
                0, 0,
                to_dpi_aware_pixels(100), to_dpi_aware_pixels(200),
                m_mainWnd,
                nullptr,
                m_hInstance,
                nullptr
            );
        assert(m_contentEditWnd);

        m_statsEditWnd = ::CreateWindowW(
            L"edit", 
            nullptr, 
            WS_CHILD | WS_VISIBLE | WS_EX_CLIENTEDGE | ES_READONLY,
            0, 0, 
            to_dpi_aware_pixels(100), to_dpi_aware_pixels(16), 
            m_mainWnd, 
            nullptr, 
            m_hInstance, 
            nullptr
        );
        assert(m_statsEditWnd);

        const HFONT hFont = [dpi=this->m_dpi]{
            NONCLIENTMETRICSW metrics;
            metrics.cbSize = sizeof(metrics);

            {
                const bool getMetrics = ::SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, metrics.cbSize, &metrics, 0, dpi);
                assert(getMetrics);
            }

            //For some fucking reason, for fonts 72 ppi is the default.
            metrics.lfMenuFont.lfHeight = 16 * dpi / 72;
            HFONT hFont = ::CreateFontIndirectW(&metrics.lfMenuFont);
            assert(hFont);
            return hFont;
        }();
        
        ::SendMessageW(m_contentEditWnd, WM_SETFONT, (WPARAM)hFont, false);
        ::SendMessageW(m_statsEditWnd, WM_SETFONT, (WPARAM)hFont, false);
    }

    void MainWindow::layout_subcontrols() {
        constexpr int LEFT_PADDING = 0;
        constexpr int RIGHT_PADDING = 0;
        constexpr int TOP_PADDING = 0;
        constexpr int BOTTOM_PADDING = 0;
        constexpr int STATS_CONTROL_VERTICAL_SPACE = 24;

        Rect clientRect;
        if (not ::GetClientRect(m_mainWnd, &clientRect)) {
            return;
        }

        const auto effectiveStatsWndVerticalSpace = to_dpi_aware_pixels(STATS_CONTROL_VERTICAL_SPACE);

        ::MoveWindow(
            m_contentEditWnd,
            LEFT_PADDING,
            TOP_PADDING,
            clientRect.right - (LEFT_PADDING + RIGHT_PADDING),
            clientRect.bottom - clientRect.top - (TOP_PADDING + BOTTOM_PADDING) - effectiveStatsWndVerticalSpace,
            false
        );

        ::MoveWindow(
            m_statsEditWnd,
            LEFT_PADDING,
            TOP_PADDING + clientRect.get_height() - effectiveStatsWndVerticalSpace,
            clientRect.right - (LEFT_PADDING + RIGHT_PADDING),
            effectiveStatsWndVerticalSpace,
            false
        );

    }

    void MainWindow::on_save_content_command() noexcept {
        constexpr std::size_t SUGGESTED_FILE_NAME_MAX_LENGTH = 100;

        std::wstring buffer{};
        buffer.resize(33 * 1024); //TODO: put correct max wide path

        const std::wstring content = get_window_text(m_contentEditWnd);
        { //suggest the name of a file
            constexpr std::wstring_view INVALID_CHARACTERS = L"/\\<>:\"|?*"sv;
            std::size_t writePos = 0;
            for (std::size_t stopPos = 0; stopPos < (std::min)(SUGGESTED_FILE_NAME_MAX_LENGTH, content.size()); ++stopPos, ++writePos) {
                const wchar_t currentChar = content[stopPos];
                if (currentChar == L'\r' or currentChar == L'\n') {
                    break;
                }
                else if (INVALID_CHARACTERS.find(currentChar) != std::wstring_view::npos) {
                    buffer[writePos] = L'!';
                }
                else {
                    buffer[writePos] = currentChar;
                }
            }

            if (writePos == 0) {
                constexpr std::wstring_view EMPTY_NAME = L"(empty)"sv;
                std::memcpy(buffer.data(), EMPTY_NAME.data(), EMPTY_NAME.size() * sizeof(wchar_t));
            }
        }
        

        OPENFILENAMEW saveFileDialogSettings{ 0 };
        saveFileDialogSettings.lStructSize = sizeof(OPENFILENAMEW);
        saveFileDialogSettings.hwndOwner = m_mainWnd;
        saveFileDialogSettings.lpstrFile = buffer.data();
        saveFileDialogSettings.nMaxFile = buffer.size();
        saveFileDialogSettings.lpstrFileTitle;
        saveFileDialogSettings.Flags = OFN_DONTADDTORECENT | OFN_FORCESHOWHIDDEN | OFN_LONGNAMES | OFN_NOTESTFILECREATE;

        if (not ::GetSaveFileNameW(&saveFileDialogSettings)) {

            const DWORD err = CommDlgExtendedError();
            if (const bool isCancelled = (err == 0); isCancelled) {
                return;
            }

            const std::wstring errorMessage = std::format(L"Extended error code : {}.", err);
            ::MessageBoxW(m_mainWnd, errorMessage.c_str(), L"::GetSaveFileNameW() failed", MB_OK | MB_ICONERROR);
            return;
        }

        //resize the file name buffer to exact content size
        for (std::size_t i = saveFileDialogSettings.nFileOffset; i < buffer.size(); ++i) {
            if (buffer[i] == 0) {
                buffer.resize(i);
                break;
            }
        }

        if (buffer.size() >= MAX_PATH and (not buffer.starts_with(L"\\\\?\\"sv)) ){
            buffer.insert(0, L"\\\\?\\"sv);
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

        const std::string contentInUtf8Encoding = helpers::to_string(content);

        if (not write_to_file(hFile, contentInUtf8Encoding.data(), contentInUtf8Encoding.size())) {
            const DWORD lastError = ::GetLastError();
            const auto errorDescription = helpers::get_error_message_w(lastError);
            const std::wstring errorMessage = std::format(L"{}(error code = {})", errorDescription.get(), lastError);
            return;
        }


    }

    void MainWindow::on_content_changed() noexcept{
        m_bufferForContent.clear();
        get_window_text(m_contentEditWnd, m_bufferForContent);

        //TODO: also optimize, to many copying back and forth.
        if (m_bufferForContent.empty()) {
            ::SetWindowTextW(m_mainWnd, APP_NAME_EMPTY);
            return;
        }

        const Statistics numberStats = Statistics::from_string(m_bufferForContent);
        numberStats.to_string(m_bufferForStats);
        ::SetWindowTextW(m_statsEditWnd, m_bufferForStats.c_str());

        const std::size_t contentSize = m_bufferForContent.size();
        {
            std:size_t offset{ 0 };
            for (wchar_t c : m_bufferForContent) {
                if (c == L'\n' or c == L'\r') {
                    m_bufferForContent.erase(offset);
                    break;
                }
                ++offset;
            }
        
        }

        m_bufferForContent.append(std::format(L" -- {} ({} wchars)", APP_NAME, contentSize));
        ::SetWindowTextW(m_mainWnd, m_bufferForContent.c_str());
    }

    void MainWindow::on_dpi_changed(std::uint32_t newDPI, const RECT* suggestedNewRect) noexcept{
        m_dpi = newDPI;

        const Rect& rect{ *suggestedNewRect };
        ::SetWindowPos(m_mainWnd, nullptr, rect.left, rect.top, rect.get_width(), rect.get_height(), SWP_NOZORDER | SWP_NOACTIVATE);
    }

    std::uint32_t MainWindow::to_dpi_aware_pixels(std::uint32_t defaultDPIPixels) const noexcept{
        return static_cast<std::uint32_t>(static_cast<std::uint64_t>(defaultDPIPixels) * m_dpi / DEFAULT_NON_SCALED_DPI);
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
                const long effectiveWidth = (std::max)(r.get_width(), (LONG)to_dpi_aware_pixels(400));
                const long effectiveHeight = (std::max)(r.get_height(), (LONG)to_dpi_aware_pixels(200));
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
                    ::SetFocus(m_contentEditWnd);
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
                if (lParam == (LPARAM)m_contentEditWnd) {
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

        //if (const bool isOneOfMyWindows = (msg.hwnd == m_mainWnd or msg.hwnd == m_contentEditWnd or msg.hwnd == m_statsEditWnd); not isOneOfMyWindows) {
        //    return false; // not my window, don't care.
        //}

        //intercept all C+ENTER
        if (message != WM_KEYUP and message != WM_KEYDOWN) {
            return false;
        }

        if (wParam == VK_ESCAPE and message == WM_KEYDOWN) {
            ::PostQuitMessage(0);
            return true;
        }

        if (message == WM_KEYDOWN) {
            if (wParam == VK_TAB) {
                const HWND currentFocusedWnd = ::GetFocus();
                //const bool traverseBackward = is_button_down(VK_SHIFT);
                if (currentFocusedWnd == m_contentEditWnd) {
                    ::SetFocus(m_statsEditWnd);
                    //also automatically select all content of the control (it is readonly, so it's completely safe)
                    ::PostMessageW(m_statsEditWnd, EM_SETSEL, 0, -1);
                    return true;
                }
                else if (currentFocusedWnd == m_statsEditWnd) {
                    ::SetFocus(m_contentEditWnd);
                    return true;
                }
            }
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
                    const HWND focusedWnd = ::GetFocus();
                    ::PostMessageW(focusedWnd, EM_SETSEL, 0, -1);
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
