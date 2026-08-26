# Creature TV: navigation rebuilt on a native TabView

Tracking issue: [#72](https://github.com/opsnlops/creature-console/issues/72).

## The problem

The TV reused `TopContentView`'s `NavigationSplitView` — a desktop idiom. On tvOS, split-view
sidebar-push navigation fights the remote's focus model: once focus lands in a pushed
full-screen view (the sACN monitor being the worst offender), there is no rail back to the
sidebar. Screens become roach motels.

## The fix

Blow it up (April's words). TV gets its own root:

- **`TVRootView`**: a `TabView` with `.tabViewStyle(.sidebarAdaptable)` — the native floating
  tvOS sidebar. Swiping up / Menu from any tab root reveals it; it is *always* reachable.
- **One `NavigationStack` per tab.** Menu pops toward the tab root by construction; at the
  root it surfaces the tab bar. Dead ends become structurally impossible.
- Tabs: Creatures, Live Magic, Animations, Soundboard, Spatial Audition, Monitoring, Settings.
- **Monitoring** unifies the two live-network monitors (sACN universes and stage audio) plus
  the joystick inspector. The monitors previously diverged completely — sACN configured in
  Settings under a dedicated sidebar item, audio configured inline on its own tab. Now both
  read one shared relay host (`relayHost`, default `10.69.66.1`) plus per-service ports from
  a single **Settings › Network Monitors** card, since both relays run on the same
  VLAN-connected machine (`creature-cli network sacn-listen` / `rtp-listen`).
- `RootView` keeps the shared bootstrap/alert/websocket plumbing and simply branches:
  `TVRootView` on tvOS, `TopContentView` everywhere else. The `#if os(tvOS)` sections come
  out of `TopContentView`'s sidebar.
- The floating status toolbar stays as a `ZStack` overlay in `TVRootView`, still honoring the
  `hideBottomToolbar` preference that full-screen views (sACN monitor) set.
- `CreatureDetailTV.swift` stays: despite the filename, it *declares* the tvOS
  `struct CreatureDetail` (the Console target has its own file of that type). A rename to
  match would be nice someday, but target-scoped same-name types are how the two platforms
  diverge here, and this pass doesn't touch it.

## Non-goals

No content-screen redesigns in this pass (the soundboard, animation triggers, etc. keep their
internals); this is the navigation skeleton. Screens that earn a redesign get their own issues
once you can actually reach and leave all of them.
