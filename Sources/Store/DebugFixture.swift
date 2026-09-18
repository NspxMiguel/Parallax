#if DEBUG

    import Foundation

    extension ChatSession {
        /// Fills the transcript with a canned exchange so the reply layout,
        /// compare mode and Markdown rendering can be seen on a simulator with
        /// no API key and no network:
        ///
        ///     PARALLAX_DEMO=1 PARALLAX_LANG=pt xcrun simctl launch …
        ///
        /// Debug builds only; it never ships.
        func loadDebugFixtureIfRequested() {
            guard ProcessInfo.processInfo.environment["PARALLAX_DEMO"] == "1" else { return }

            var conversation = Conversation()
            conversation.title = "Parallax in one paragraph"
            conversation.providers = [.claude, .gemini]

            var exchange = Exchange(
                prompt: ChatMessage(
                    role: .user,
                    text: "Explain parallax to someone wearing a headset, and show it in code."
                )
            )
            exchange.replies = [
                ChatMessage(
                    role: .assistant,
                    text: """
                        Hold a finger up and close one eye, then the other: the finger \
                        jumps against the background. That jump is **parallax**, and the \
                        size of it is how your brain measures distance.

                        ```swift
                        let offset = separated ? size * 0.26 : size * 0.09
                        ```

                        A headset draws two images a few centimetres apart for the same \
                        reason — depth is the difference between them.
                        """,
                    reasoning: "The clearest demonstration is the one they can do without "
                        + "any equipment, so lead with the finger rather than with astronomy.",
                    provider: .claude,
                    modelID: "claude-opus-5"
                ),
                ChatMessage(
                    role: .assistant,
                    text: """
                        Parallax is the apparent shift of an object when the observer \
                        moves. Astronomers measure star distances with it, using Earth's \
                        orbit as the baseline; a headset uses the gap between your eyes.

                        ```swift
                        let depth = baseline / tan(angle)
                        ```

                        Same formula, different baseline.
                        """,
                    reasoning: "Give the measurable definition first, then tie the two "
                        + "baselines together.",
                    provider: .gemini,
                    modelID: "gemini-2.5-pro"
                ),
            ]
            conversation.exchanges = [exchange]

            conversations.insert(conversation, at: 0)
            selectedID = conversation.id
        }
    }

#endif
