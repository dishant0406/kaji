import Foundation

enum MarkdownWebBridge {
    static let scrollHandlerName = "muxyMarkdownScroll"
    static let wheelHandlerName = "muxyMarkdownWheel"

    static let scrollObserverScript = #"""
    (() => {
        const handler = window.webkit?.messageHandlers?.muxyMarkdownScroll;
        if (!handler) return;

        let attachedRoot = null;
        let wheelListener = null;
        let reportScheduled = false;

        const scrollRoot = () => document.getElementById('content')
            || document.scrollingElement
            || document.documentElement
            || document.body;

        const reportNow = () => {
            const root = scrollRoot();
            if (!root) return;
            handler.postMessage({
                scrollTop: root.scrollTop,
                scrollHeight: root.scrollHeight,
                clientHeight: root.clientHeight,
            });
        };

        const scheduleReport = () => {
            if (reportScheduled) return;
            reportScheduled = true;
            requestAnimationFrame(() => {
                reportScheduled = false;
                reportNow();
            });
        };

        const attach = () => {
            const root = scrollRoot();
            if (!root) return;

            if (attachedRoot === root) {
                scheduleReport();
                return;
            }

            if (attachedRoot) {
                attachedRoot.removeEventListener('scroll', scheduleReport);
                if (wheelListener) {
                    attachedRoot.removeEventListener('wheel', wheelListener);
                }
            }

            wheelListener = event => {
                if (!document.documentElement?.classList.contains('muxy-linked-scroll')) return;
                event.preventDefault();
                event.stopPropagation();
            };

            attachedRoot = root;

            root.addEventListener('scroll', scheduleReport, { passive: true });
            root.addEventListener('wheel', wheelListener, { passive: false });
            scheduleReport();
        };

        window.addEventListener('resize', scheduleReport, { passive: true });
        window.addEventListener('load', () => setTimeout(attach, 0));
        document.addEventListener('DOMContentLoaded', () => setTimeout(attach, 0));
        setTimeout(attach, 0);
    })();
    """#

    static func scrollToSyncPointScript(_ point: MarkdownSyncPoint) -> String {
        let escapedAnchorID = point.anchorID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let anchorLine = max(point.startLine, 1)
        let startLine = max(point.startLine, 1)
        let endLine = max(point.endLine, startLine)
        let progress = min(max(point.localProgress, 0), 1)
        return """
        (() => {
            const root = document.getElementById('content')
                || document.scrollingElement
                || document.documentElement
                || document.body;
            if (!root) return;

            const desiredStart = \(startLine);
            const desiredEnd = \(endLine);
            const desiredLine = \(anchorLine);
            const localProgress = \(progress);
            const desiredAnchorID = "\(escapedAnchorID)";

            const rootRect = root.getBoundingClientRect();
            const nodes = Array.from(document.querySelectorAll('[data-muxy-line-start][data-muxy-line-end]'));
            if (!nodes.length) return;

            const candidate = nodes.find(el => {
                const anchorID = el.getAttribute('data-muxy-anchor-id');
                return anchorID && anchorID === desiredAnchorID;
            }) || nodes.find(el => {
                const s = parseInt(el.getAttribute('data-muxy-line-start') || '0', 10);
                const e = parseInt(el.getAttribute('data-muxy-line-end') || '0', 10);
                return s === desiredStart && e === desiredEnd;
            }) || nodes.find(el => {
                const s = parseInt(el.getAttribute('data-muxy-line-start') || '0', 10);
                const e = parseInt(el.getAttribute('data-muxy-line-end') || '0', 10);
                return s <= desiredLine && desiredLine <= e;
            }) || nodes[0];

            const rect = candidate.getBoundingClientRect();
            const top = rect.top - rootRect.top + root.scrollTop;
            const height = Math.max(1, rect.height);
            const maxScrollTop = Math.max(0, root.scrollHeight - root.clientHeight);
            var target = top + localProgress * height;

            const firstNode = nodes[0];
            const lastNode = nodes[nodes.length - 1];
            if (candidate === firstNode && localProgress <= 0.001) {
                target = 0;
            }
            if (candidate === lastNode && localProgress >= 0.999) {
                const alignedBottomTarget = Math.max(0, top + height - root.clientHeight);
                target = Math.min(target, alignedBottomTarget);
            }

            target = Math.min(maxScrollTop, Math.max(0, target));

            window.__muxyProgrammaticScroll = true;
            root.scrollTop = target;
            setTimeout(() => { window.__muxyProgrammaticScroll = false; }, 180);
        })();
        """
    }
}
