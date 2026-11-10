# Neiv UI components

The component library has two layers:

- `fundamental/` owns reusable interaction and appearance without photographic meaning. `StepButton.weiv` owns the shared circular `−`/`+` control. `StepRange.weiv` owns range input, bounds, step buttons, and the handle reset gesture. It emits numeric `preview`, `commit`, and `step` events, plus `reset`.
- `domain/` composes fundamental components around photography concepts. `DevelopSlider.weiv` adds the edit name, photographic help, formatted value, and range captions. It forwards events with the edit ID. Photo state and Cyna commands stay in `App.weiv`.

Pass custom component string literals as bound expressions, such as `:id="'exposure'"`. Until the nested conditional component issue in Weiv is fixed, keep the tab panels and sliders mounted and hide inactive ones with CSS.

The bundled Weiv 0.1.2 used by the Neiv build rejects template literals in
component prop bindings. Compute them in script instead, such as
`:label="decreaseLabel()"`.
