# Luma agent instructions

These rules apply to every change in this repository. They are especially
important for changes under `mobile/`, which is the Flutter application.

## Working agreement

- Preserve unrelated, existing worktree changes. Do not revert or reformat
  unrelated files.
- Prefer the smallest complete fix. Keep deep links and error/retry paths
  working when adding a fast path for in-app navigation.
- For Flutter changes, run `flutter analyze` from `mobile/`, plus focused
  widget/unit tests for the affected feature. Run `git diff --check` before
  handing work off.

## Code documentation rules

- 所有新增或修改的代码注释必须使用简洁、自然的中文；避免模板化、冗长或带有 AI 生成痕迹的表述。
- Every new source file must start with a concise header comment describing
  the file's responsibility, its primary collaborators, and any important
  lifecycle or state-management constraint.
- Every new or materially changed public function, method, and callback must
  have a doc comment that states what it does, its important side effects,
  and any non-obvious preconditions or failure behavior.
- Document private functions when their intent is not immediately clear from
  their name and short body. Do not add filler comments that merely restate
  obvious code.
- Keep comments accurate when changing behavior. Updating implementation
  without updating its relevant documentation is incomplete work.

## Flutter page composition

- Page files should own route arguments, lifecycle, loading/error state, and
  mutations only. Move independent display regions such as heroes, metadata
  sections, lists, and tiles into `features/<feature>/widgets/`.
- Do not let a detail page accumulate several unrelated visual components.
  When a page needs multiple display regions, compose dedicated widgets and
  keep shared visual tokens in a nearby theme or token file.

## UI motion and overlay rules

The app must feel immediate and visually clean. Treat a stale frame, lingering
scrim, or whole-page loading flash as a defect.

- Give each interaction one source of motion. Do not stack a route transition,
  Hero flight, dialog fade, keyboard animation, or custom opacity animation
  unless the combined result has been explicitly verified.
- Dialogs and sheets must cleanly remove their barrier, focus, keyboard, and
  shadows when dismissed. Do not leave a semi-transparent overlay or stale
  elevation visible after Cancel or Back.
- Card taps must not add an unintended grey/black splash or overlay. Only add
  a pressed-state effect when it is intentional, brief, and tested against
  light and dark artwork.
- Do not disable all navigation animation by default. Use a no-transition
  route only when a normal route transition demonstrably produces a residual
  or conflicts with another intended animation.

## Navigation and first-frame data rules

- When a list/grid item opens a detail, editor, or action page, pass the
  selected model as route data (`extra` / `initialItem`) and render it on the
  first frame. Refresh complete data in the background.
- A page reached from a deep link may start without route data. It must retain
  a useful app bar and a layout-stable loading state while it fetches.
- Do not re-fetch a list solely to rediscover an object the previous page
  already has. Use the passed object, then refresh only data that is actually
  needed.
- When opening a full list from a summary shelf, pass the visible shelf items
  into the destination and keep them on screen while its first paged refresh
  runs. Do not enter the destination with an empty grid if usable cards are
  already rendered on the source page.
- A refresh must retain existing content. Show a local progress indicator,
  inline status, or top progress line, never replace populated content with a
  full-page loading spinner.

## Loading-state rules

- For an initial page load, use a skeleton whose spacing and hierarchy match
  the resolved page. Do not use a centered, full-page `CircularProgressIndicator`
  when the final page is a list, form, or detail layout.
- Keep loading, empty, error, and ready states separate. An error must not
  erase valid stale content unless that content is known to be invalid.
- Prefer a shared skeleton component over adding one-off loading layouts.

## Media-card rules

- Never stretch artwork. Preserve the source aspect ratio and use an explicit
  `BoxFit`/resize policy appropriate to its card type.
- Decorative controls over artwork, including favorite icons, must remain
  legible on both light and dark covers without adding a persistent opaque
  badge unless the design explicitly requires one.
- A Hero flight from a media card must use the same thumbnail variant at both
  ends of the flight. Do not start decoding a larger detail image until the
  Hero and route transition have settled.
- When the source and destination can resolve the same thumbnail at different
  cache sizes, provide a Hero flight shuttle that keeps the already decoded
  source child. Do not rely on the target image provider becoming ready during
  the flight, and do not swap providers on a fixed timer while the flight is
  still visible.
- Do not use Hero for video-card-to-detail navigation. Use a short,
  opacity-only route transition and defer detail work until it completes;
  this avoids scaling a video cover while the platform is also compositing a
  page transition.
- Do not start a detail request that can replace artwork or notify a shared
  media store during a Hero/route transition. Defer that work until the
  transition finishes, and cancel or ignore it if the destination is gone.
- Image preview routes must initially reuse the source thumbnail. Delay an
  original/full-resolution image request and decode until the Hero and modal
  transition have completed; keep the thumbnail visible until the original is
  ready.
- Before pushing a route, do not emit a global state notification when only a
  detail-cache entry changes. Notify only consumers whose visible data changed,
  otherwise the source page may rebuild during its own outgoing transition.

## Required interaction checks for affected UI

Before declaring a UI change complete, verify the relevant paths:

1. Tap to enter the page or dialog.
2. Dismiss it with Cancel/Back and confirm no overlay, shadow, or keyboard
   residue remains.
3. Load, refresh, and error/retry states, confirming content does not jump
   from a blank page to a full page.
4. Check at least one light and one dark media thumbnail when changing card
   overlays, aspect ratios, or press effects.
5. Profile or at least manually check the first transition with a cold image
   cache when changing Hero, full-resolution image, or shared media-state code.
