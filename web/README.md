# tiltann_banking UI

Vite, React, TypeScript and Tailwind CSS v4 (via `@tailwindcss/vite`). One bundle renders both screens that `client/ui/bank_ui.lua` can open: the ATM (`mode: 'atm'`) and the bank terminal (`mode: 'terminal'`). You only need this folder if you change the UI, `dist/` is committed.

## Setup

```
npm install
npm run dev     # browser preview with fixture data (src/api/fixtures.ts)
npm run build   # tsc -b && vite build, writes dist/
```

Commit `dist/` with any change in `src/`. Outside the game, `fetchNui` (`src/api/nui.ts`) notices there is no NUI runtime and returns mock data, so you can work in a normal browser.

Colors are CSS custom properties (`var(--tb-surface)` and so on) set at runtime from `Config.UI.Colors` by `state/theme.ts`. Shared class strings are in `src/ui-classes.ts`.

## Structure

* `src/App.tsx`: open and close handling, theme, switch between ATM and terminal.
* `src/components/AtmScreen.tsx`: card picker, PIN pad, then balance, quick withdraw, deposit, withdraw, transfer.
* `src/components/PersonalTab.tsx` and `BusinessTab.tsx`: the two terminal tabs.
* `src/components/*Panel.tsx`: cards, invoices, loans, standing orders, staff.
* `src/i18n/`: English and German strings. `error.<key>` entries cover every `errorKey` the server can return.
* `src/types.ts`: hand written copies of the Lua data shapes.

## Data flow

* Lua opens the UI with `SendNUIMessage({ action = 'open', mode = ..., ... })`. The message carries colors, currency symbol, language, feature flags and the initial data. Lua sends `action = 'refresh'` when balances change.
* Every NUI callback is named `tiltann_banking:ui:*`. In `client/ui/bank_ui.lua` each one forwards to a server `lib.callback`, and the result comes back as `{ ok, errorKey?, value? }`.
* Closing (button or Escape) calls `tiltann_banking:ui:close`.
