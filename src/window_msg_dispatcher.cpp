#include "./window_msg_dispatcher.h"
#include <stdexcept>
#include <unordered_map>

namespace {
    using namespace w;

    WindowMsgDispatcher* INSTANCE{ nullptr };

} // namespace

namespace w {

    class WindowMsgDispatcher::Impl final {
    public:
        Impl()
            : _enqueuedProcessor(nullptr)
            , _map()
        {

        }

        LRESULT process_message(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
            auto it = _map.find(hWnd);
            if (it == _map.end()) {
                if (_enqueuedProcessor == nullptr) {
                    throw std::logic_error("A message to unknown HWND came, but no processor enqueued");
                }
                _map.insert({hWnd, _enqueuedProcessor});
                auto const tmp = _enqueuedProcessor;
                _enqueuedProcessor = nullptr;
                return tmp->process_message(hWnd, message, wParam, lParam);
            }

            return it->second->process_message(hWnd, message, wParam, lParam);
        }

        void bind_to_next_new_window(IWindowMsgProcessor& processor) {
            if (_enqueuedProcessor) {
                throw std::logic_error("There is already a window processor enqueued");
            }
            _enqueuedProcessor = &processor;
        }

        void unbind(HWND what) {
            _map.erase(what);
        }

    private:
        IWindowMsgProcessor* _enqueuedProcessor;
        std::unordered_map<HWND, IWindowMsgProcessor*> _map;

    public:
        static void kill(WindowMsgDispatcher::Impl* what) {
            delete what;
        }
    };

    WindowMsgDispatcher::WindowMsgDispatcher()
        : _pImpl(nullptr, &WindowMsgDispatcher::Impl::kill)
    {
        if (INSTANCE != nullptr) {
            throw std::logic_error("WindowMsgDispatcher is already instantiated");
        }

        _pImpl = std::unique_ptr<WindowMsgDispatcher::Impl, WindowMsgDispatcher::ImplDeleter*>(new Impl(), &WindowMsgDispatcher::Impl::kill);

        INSTANCE = this;
    }

    WindowMsgDispatcher::~WindowMsgDispatcher() {
        INSTANCE = nullptr;
    }

    LRESULT WindowMsgDispatcher::process_message(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
        return _pImpl->process_message(hWnd, message, wParam, lParam);
    }

    void WindowMsgDispatcher::bind_to_next_new_window(IWindowMsgProcessor& processor) {
        return _pImpl->bind_to_next_new_window(processor);
    }

    void WindowMsgDispatcher::unbind(HWND what) {
        return _pImpl->unbind(what);
    }

    LRESULT WindowMsgDispatcher::DispatchingProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
        return INSTANCE->process_message(hWnd, message, wParam, lParam);
    }

} //namespace
