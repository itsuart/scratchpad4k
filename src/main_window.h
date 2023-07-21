#pragma once
#include <cstdint>
#include <string>

#define NOMINMAX
#include <Windows.h>
#undef NOMINMAX

#include "./window_msg_dispatcher.h"

namespace w {

    class MainWindow final : private IWindowMsgProcessor {
    public:
        MainWindow(WindowMsgDispatcher& dispatcher, HINSTANCE hInstance);

        // returns true if message was handled and therefore need not be dispatched
        bool preview_message(const MSG& msg);

    private:
        virtual LRESULT process_message(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) noexcept;

        void create_subcontrols();

        void layout_subcontrols();

        void on_save_content_command() noexcept;

        void on_content_changed() noexcept;

        void on_dpi_changed(std::uint32_t newDPI, const RECT* suggestedNewRect) noexcept;

        std::uint32_t to_dpi_aware_pixels(std::uint32_t defaultDPIPixels) const noexcept;

    private:
        std::wstring m_bufferForContent{};
        std::wstring m_bufferForStats{};

        HINSTANCE m_hInstance;

        HWND m_mainWnd;
        HWND m_contentEditWnd;
        HWND m_statsEditWnd;

        std::uint32_t m_dpi;
    };
} //namespace
