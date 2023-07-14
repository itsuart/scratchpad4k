#pragma once
#include <Windows.h>
#include <memory>

namespace w {

    struct IWindowMsgProcessor {
        virtual LRESULT process_message(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) = 0;
    };

    // maps HWND -> IWindowHandler
    class WindowMsgDispatcher final {
        class Impl;
        using ImplDeleter = void(Impl*);
    public:
        WindowMsgDispatcher();

        ~WindowMsgDispatcher();

        //next non-bound HWND will be bound to the processor
        void bind_to_next_new_window(IWindowMsgProcessor& processor);

        void unbind(HWND what);

    private:
        LRESULT process_message(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam);

    public:
        static LRESULT DispatchingProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam);

    private:
        std::unique_ptr<Impl, ImplDeleter*> _pImpl;
    };

} //namespace
