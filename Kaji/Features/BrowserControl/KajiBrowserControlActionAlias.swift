import Foundation

enum KajiBrowserControlActionAlias {
    static func resolve(_ action: String) -> String {
        aliases[action] ?? action
    }

    private static let aliases = [
        "browser_close": "close",
        "browser_resize": "resize",
        "browser_console_messages": "console_messages",
        "browser_handle_dialog": "handle_dialog",
        "browser_evaluate": "eval",
        "browser_file_upload": "file_upload",
        "browser_drop": "drop",
        "browser_fill_form": "fill_form",
        "browser_press_key": "press_key",
        "browser_type": "type",
        "browser_navigate": "navigate",
        "browser_navigate_back": "back",
        "browser_navigate_forward": "forward",
        "browser_reload": "reload",
        "browser_network_requests": "network_requests",
        "browser_network_request": "network_request",
        "browser_take_screenshot": "screenshot",
        "browser_snapshot": "snapshot",
        "browser_click": "click",
        "browser_drag": "drag",
        "browser_hover": "hover",
        "browser_select_option": "select_option",
        "browser_tabs": "tabs",
        "browser_wait_for": "wait",
    ]
}
