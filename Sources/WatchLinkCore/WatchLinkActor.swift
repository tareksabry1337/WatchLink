/// Global actor that serializes all WatchLink and WatchLinkHost operations.
///
/// Public types annotated `@WatchLinkActor` share this single isolation domain, so
/// you can call `send`, `reply`, and `messages` from any task without data races.
@globalActor
public actor WatchLinkActor {
    /// Shared instance used by every `@WatchLinkActor`-isolated declaration.
    public static let shared = WatchLinkActor()
    private init() {}
}
