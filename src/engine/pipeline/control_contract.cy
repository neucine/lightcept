// The typed, versioned develop control contract.
//
// Cyna owns this table: every control name a recipe may carry, the family it belongs to, the
// units its number is in, the value that leaves the image unchanged, the scopes it admits, and
// the value range each scope and mode accepts. A product caller may format
// messages; Cyna owns every control id, bound, neutral value, and scope.
//
// A control-contract revision is reproducible only while this table still carries that revision's
// exact bounds. A future revision that changes a range adds its own rows so projects pinned to an
// older revision keep replaying.
import .engine.pipeline.develop_stage_manifest;
import .engine.develop.edit_plan;

const control_contract_version: u32 = 2;
const control_name_bytes: usize = 24;
const control_units_bytes: usize = 24;
const control_label_bytes: usize = 48;
const control_descriptor_bytes: usize = 256;
const max_declared_controls: usize = 64;
const max_value_domains: usize = 4;
const max_reproducible_revisions: usize = 8;

// Scope, mode, and family codes shared with the host.
pub const scope_global: u32 = 1;
pub const scope_local: u32 = 2;
pub const scope_both: u32 = 3;
// These are the version-2 control-contract transport codes. The logical
// develop plan uses delta=2; its mode must be converted by meaning.
pub enum ControlMode: u32 {
    delta = 0,
    target = 1,
}
pub const mode_delta: u32 = 0;
pub const mode_target: u32 = 1;

// Translate only an admitted transport mode before compiling a logical plan.
// Equal numeric values for target are incidental; delta differs across them.
pub fn logical_plan_mode(mode: u32): ?u32 {
    if mode == ControlMode.delta as u32 {
        return edit_plan.mode_delta;
    }
    if mode == ControlMode.target as u32 {
        return edit_plan.mode_target;
    }
    return none;
}

pub enum ControlFamily: u32 {
    capture_colour = 1,
    tone = 2,
    chroma = 3,
    detail = 4,
    geometry = 5,
    mask = 6,
    output = 7,
    analysis = 8,
}

// Edit-validation status codes. The host turns these into product errors; the decision lives here.
pub const edit_ok: u32 = 0;
pub const edit_unknown_control: u32 = 1;
pub const edit_declared_stage: u32 = 2;
pub const edit_scope_mismatch: u32 = 3;
pub const edit_mode_unavailable: u32 = 4;
pub const edit_out_of_range: u32 = 5;
pub const edit_revision_unreproducible: u32 = 6;
pub const edit_non_finite: u32 = 7;
pub const edit_transport: u32 = 255;

// One accepted value range for one scope and one mode.
pub struct ValueDomain {
    pub scope: u32;
    pub mode: u32;
    pub min: f64;
    pub max: f64;
}

// Up to four value domains per control: delta and target for the admitted scopes.
pub struct ControlContractEntry {
    pub name: string;
    pub label: string;
    pub family: u32;
    pub units: string;
    pub neutral: f64;
    pub scope: u32;
    pub domain_count: u32;
    pub first: ValueDomain;
    pub second: ValueDomain;
    pub third: ValueDomain;
    pub fourth: ValueDomain;
}

fn domain(scope: u32, mode: u32, min: f64, max: f64): ValueDomain {
    return {
        scope: scope,
        mode: mode,
        min: min,
        max: max
    };
}

fn unused_domain(): ValueDomain {
    return {
        scope: 0,
        mode: 0,
        min: 0.0,
        max: 0.0
    };
}

fn control(name: string, label: string, family: ControlFamily, units: string, neutral: f64, scope: u32, first: ValueDomain, second: ValueDomain, third: ValueDomain, fourth: ValueDomain): ControlContractEntry {
    var count: u32 = 0;
    if first.scope > 0 {
        count = count + 1;
    }
    if second.scope > 0 {
        count = count + 1;
    }
    if third.scope > 0 {
        count = count + 1;
    }
    if fourth.scope > 0 {
        count = count + 1;
    }
    return {
        name: name,
        label: label,
        family: family as u32,
        units: units,
        neutral: neutral,
        scope: scope,
        domain_count: count,
        first: first,
        second: second,
        third: third,
        fourth: fourth
    };
}

// A control whose delta and target range is the same in every admitted scope.
fn percent_control(name: string, label: string, family: ControlFamily, units: string, scope: u32): ControlContractEntry {
    return control(name, label, family, units, 0.0, scope,
        domain(scope, mode_delta, -100.0, 100.0),
        domain(scope, mode_target, -100.0, 100.0),
        unused_domain(),
        unused_domain()
    );
}

// Every control an edit recipe may carry, in contract order. The order is the order the editor
// and the planner advertise controls, so a control index always means the same row here.
fn control_rows(): [:]ControlContractEntry {
    return [
        control("exposure", "Exposure", ControlFamily.capture_colour, "EV stops", 0.0, scope_both,
            domain(scope_both, mode_delta, -4.0, 4.0),
            domain(scope_both, mode_target, -4.0, 4.0),
            unused_domain(),
            unused_domain()
        ),
        control("contrast", "Contrast", ControlFamily.tone, "percent", 0.0, scope_both,
            domain(scope_both, mode_delta, -100.0, 100.0),
            domain(scope_both, mode_target, -100.0, 100.0),
            unused_domain(),
            unused_domain()
        ),
        control("temp", "Color temperature", ControlFamily.capture_colour, "kelvin globally, relative units locally", 0.0, scope_both,
            domain(scope_global, mode_delta, -5000.0, 5000.0),
            domain(scope_global, mode_target, 2000.0, 50000.0),
            domain(scope_local, mode_delta, -100.0, 100.0),
            domain(scope_local, mode_target, -100.0, 100.0)
        ),
        control("tint", "Green-magenta tint", ControlFamily.capture_colour, "relative units", 0.0, scope_both,
            domain(scope_both, mode_delta, -100.0, 100.0),
            domain(scope_both, mode_target, -100.0, 100.0),
            unused_domain(),
            unused_domain()
        ),
        control("sharpening", "Capture sharpening amount", ControlFamily.detail, "amount", 0.0, scope_both,
            domain(scope_global, mode_delta, -100.0, 100.0),
            domain(scope_global, mode_target, 0.0, 150.0),
            domain(scope_local, mode_delta, -100.0, 100.0),
            domain(scope_local, mode_target, -100.0, 100.0)
        ),
        percent_control("texture", "Fine-detail texture", ControlFamily.detail, "percent", scope_both),
        percent_control("clarity", "Midtone clarity", ControlFamily.detail, "percent", scope_both),
        percent_control("dehaze", "Atmospheric dehaze", ControlFamily.detail, "percent", scope_both),
        percent_control("saturation", "Color saturation", ControlFamily.chroma, "percent", scope_both),
        percent_control("red_luminance", "Red color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("orange_luminance", "Orange color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("yellow_luminance", "Yellow color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("green_luminance", "Green color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("aqua_luminance", "Aqua color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("blue_luminance", "Blue color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("purple_luminance", "Purple color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("magenta_luminance", "Magenta color luminance", ControlFamily.chroma, "percent", scope_global),
        percent_control("highlights", "Highlight tone", ControlFamily.tone, "percent", scope_both),
        percent_control("shadows", "Shadow tone", ControlFamily.tone, "percent", scope_both),
        percent_control("whites", "White point", ControlFamily.tone, "percent", scope_both),
        percent_control("blacks", "Black point", ControlFamily.tone, "percent", scope_both),
        percent_control("hue", "Local hue shift", ControlFamily.chroma, "relative units", scope_local),
        control("color_hue", "Local color overlay hue", ControlFamily.chroma, "degrees", 0.0, scope_local,
            domain(scope_local, mode_delta, -100.0, 100.0),
            domain(scope_local, mode_target, 0.0, 360.0),
            unused_domain(),
            unused_domain()
        ),
        control("color_sat", "Local color overlay saturation", ControlFamily.chroma, "percent", 0.0, scope_local,
            domain(scope_local, mode_delta, -100.0, 100.0),
            domain(scope_local, mode_target, 0.0, 100.0),
            unused_domain(),
            unused_domain()
        ),
        percent_control("noise", "Local noise reduction", ControlFamily.detail, "percent", scope_local),
        percent_control("moire", "Local moire reduction", ControlFamily.detail, "percent", scope_local),
        percent_control("defringe", "Local defringe", ControlFamily.detail, "percent", scope_local),
        control("amount", "Local mask adjustment amount", ControlFamily.mask, "percent", 0.0, scope_local,
            domain(scope_local, mode_delta, -100.0, 100.0),
            domain(scope_local, mode_target, 0.0, 200.0),
            unused_domain(),
            unused_domain()
        )
    ];
}

// Revisions whose bounds this table still carries.
pub fn reproducible_revisions(): [:]u32 {
    return [1, 2];
}

pub fn control_is_reproducible(revision: u32): bool {
    const revisions = reproducible_revisions();
    var index: usize = 0;
    while index < revisions.len() {
        if revisions[index] == revision {
            return true;
        }
        index = index + 1;
    }
    return false;
}

// Revision 1 accepted exactly the ranges the typed table declares today. A later revision that
// narrows or widens a range must declare its own rows before it can be claimed as reproducible.
pub fn control_contract(revision: u32): [:]ControlContractEntry {
    if control_is_reproducible(revision) {
        return control_rows();
    }
    return placeholder_contract();
}

// One blank row stands for "no contract at this revision". The query rejects an unknown revision
// before a host reads it, so this only keeps the descriptor writer total.
fn placeholder_contract(): [:]ControlContractEntry {
    const empty = unused_domain();
    return [{
        name: "",
        label: "",
        family: 0,
        units: "",
        neutral: 0.0,
        scope: 0,
        domain_count: 0,
        first: empty,
        second: empty,
        third: empty,
        fourth: empty
    }];
}

fn domain_at(entry: ControlContractEntry, index: usize): ValueDomain {
    if index == 0 {
        return entry.first;
    }
    if index == 1 {
        return entry.second;
    }
    if index == 2 {
        return entry.third;
    }
    return entry.fourth;
}

fn control_row_position(revision: u32, name: string): usize {
    const rows = control_contract(revision);
    var index: usize = 0;
    while index < rows.len() {
        if rows[index].name == name {
            return index;
        }
        index = index + 1;
    }
    return rows.len();
}

// A borrowed control name arrives as C bytes. Comparing it byte by byte keeps the decision in
// Cyna without copying the name into a dynamic string.
fn name_is_named(name: *const u8, name_len: usize, candidate: string): bool {
    const bytes: []const u8 = candidate.bytes();
    if bytes.len() != name_len {
        return false;
    }
    var index: usize = 0;
    while index < name_len {
        var byte: u32 = 0;
        unchecked {
            byte = *(((name as! usize) + index) as! *const u8) as u32;
        }
        if byte != bytes[index] as u32 {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn is_declared_stage(name: string): bool {
    const stages = develop_stage_manifest.declared_stages();
    var index: usize = 0;
    while index < stages.len() {
        if stages[index].name == name {
            return true;
        }
        index = index + 1;
    }
    return false;
}

// The decision for one located control row. Scope and mode are resolved here so both the typed
// caller and the serialized transport reach the same answer.
fn decide_control(entry: ControlContractEntry, mode: u32, value: f64, local: bool): u32 {
    var scope: u32 = scope_global;
    if local {
        scope = scope_local;
    }
    if entry.scope != scope_both and entry.scope != scope {
        return edit_scope_mismatch;
    }
    var domain_index: usize = 0;
    while domain_index < entry.domain_count as usize {
        const declared = domain_at(entry, domain_index);
        if declared.mode == mode and (declared.scope == scope or declared.scope == scope_both) {
            if value < declared.min or value > declared.max {
                return edit_out_of_range;
            }
            return edit_ok;
        }
        domain_index = domain_index + 1;
    }
    return edit_mode_unavailable;
}

// Validate one adjustment. `local` is true when the recipe carries a mask, so the adjustment
// applies to the masked region only. A name that matches a declared develop stage but has no
// pinned range is reported separately from an unknown name: the capability exists, the control
// does not yet.
pub fn validate_edit(name: string, mode: u32, value: f64, local: bool, revision: u32): u32 {
    if not control_is_reproducible(revision) {
        return edit_revision_unreproducible;
    }
    if value - value != 0.0 {
        return edit_non_finite;
    }
    const rows = control_contract(revision);
    const position = control_row_position(revision, name);
    if position == rows.len() {
        if is_declared_stage(name) {
            return edit_declared_stage;
        }
        return edit_unknown_control;
    }
    return decide_control(rows[position], mode, value, local);
}

// Whether one composed stage's comma-separated driven-control list names a control. The list is
// written by the stage manifest, so this is the only place a control-to-stage link is read.
fn drives_control(driven: string, control: string): bool {
    const bytes: []const u8 = driven.bytes();
    const wanted: []const u8 = control.bytes();
    if bytes.len() == 0 or wanted.len() == 0 {
        return false;
    }
    var start: usize = 0;
    while start < bytes.len() {
        if start == 0 or bytes[start - 1] == (44 as u8) {
            var offset: usize = 0;
            while offset < wanted.len() and start + offset < bytes.len() and bytes[start + offset] == wanted[offset] {
                offset = offset + 1;
            }
            if offset == wanted.len() and (start + offset == bytes.len() or bytes[start + offset] == (44 as u8)) {
                return true;
            }
        }
        start = start + 1;
    }
    return false;
}

// How far this build executes one declared control for a characterised source. Bit 0: a composed
// stage drives it; bit 1: that stage takes values from develop edits; bits 2 and 3: it accepts a
// delta and a target respectively. A control the contract declares but no composed stage drives is
// a semantic promise, not a capability this engine can run yet.
pub fn control_execution(name: string, has_camera_matrix: bool, editable_white_balance: bool): u32 {
    var bits: u32 = 0;
    const composed = develop_stage_manifest.composed_stages(has_camera_matrix, editable_white_balance);
    var index: usize = 0;
    while index < composed.len() {
        const stage = composed[index];
        if drives_control(stage.driven_controls, name) {
            bits = bits + 1;
            if stage.edit_driven != 0 {
                bits = bits + 2;
            }
            if (stage.admitted_modes & 1) != 0 {
                bits = bits + 4;
            }
            if (stage.admitted_modes & 2) != 0 {
                bits = bits + 8;
            }
        }
        index = index + 1;
    }
    return bits;
}

fn write_padded(base: usize, offset: usize, text: string, width: usize): void {
    const bytes: []const u8 = text.bytes();
    var position: usize = 0;
    while position < width {
        var byte: u8 = 0;
        if position < bytes.len() {
            byte = bytes[position];
        }
        unchecked {
            *((base + offset + position) as! *u8) = byte as u8;
        }
        position = position + 1;
    }
}

fn write_number(base: usize, offset: usize, value: u32): void {
    unchecked {
        *((base + offset) as! *u32) = value as u32;
    }
}

fn write_double(base: usize, offset: usize, value: f64): void {
    unchecked {
        *((base + offset) as! *f64) = value as f64;
    }
}

// Everything a caller needs to explain one control without keeping its own copy of the table:
// whether the name is declared, the scope the contract admits, the status of the request, and the
// range the request resolved to.
pub struct ControlAdmission {
    pub found: bool;
    pub scope: u32;
    pub status: u32;
    pub domain_index: usize;
    pub min: f64;
    pub max: f64;
}

// The revision a new render contract pins.
pub fn current_contract_revision(): u32 {
    return control_contract_version;
}

// One control in a fixed 256-byte descriptor: 24 bytes of NUL-padded control name, family, scope,
// domain count, four reserved zero bytes, 24 bytes of units, the neutral value, four value domains
// of scope, mode, minimum, and maximum, 48 bytes of NUL-padded display label, and 16 reserved
// zero bytes.
fn write_descriptor(base: usize, index: usize, entry: ControlContractEntry): void {
    const slot = base + index * control_descriptor_bytes;
    write_padded(slot, 0, entry.name, control_name_bytes);
    write_number(slot, 24, entry.family);
    write_number(slot, 28, entry.scope);
    write_number(slot, 32, entry.domain_count);
    write_padded(slot, 40, entry.units, control_units_bytes);
    write_double(slot, 64, entry.neutral);
    var domain_index: usize = 0;
    while domain_index < max_value_domains {
        const offset = slot + 72 + domain_index * 24;
        if domain_index < entry.domain_count as usize {
            const declared = domain_at(entry, domain_index);
            write_number(offset, 0, declared.scope);
            write_number(offset, 4, declared.mode);
            write_double(offset, 8, declared.min);
            write_double(offset, 16, declared.max);
        } else {
            write_number(offset, 0, 0);
            write_number(offset, 4, 0);
            write_double(offset, 8, 0.0);
            write_double(offset, 16, 0.0);
        }
        domain_index = domain_index + 1;
    }
    write_padded(slot, 192, entry.label, control_label_bytes);
    var trailing: usize = 240;
    while trailing < control_descriptor_bytes {
        unchecked {
            *((slot + trailing) as! *u8) = 0;
        }
        trailing = trailing + 1;
    }
}

// Report the control contract for one revision. Status: 0 success, 2 limit, 3 shape,
// 4 revision this build cannot reproduce. `revisions` receives the revisions this build can
// replay, in ascending order, and `reproducible_count` says how many of them were written.
fn describe_control_contract(
    revision: i32,
    controls: *u8,
    controls_len: usize,
    control_count: *u32,
    control_count_len: usize,
    contract_version: *u32,
    contract_version_len: usize,
    revisions: *u32,
    revisions_len: usize,
    reproducible_count: *u32,
    reproducible_count_len: usize
): i32 {
    if controls_len as usize != max_declared_controls * control_descriptor_bytes
    or control_count_len as usize != 1
    or contract_version_len as usize != 1
    or revisions_len as usize != max_reproducible_revisions
    or reproducible_count_len as usize != 1 {
        return 3;
    }
    const wanted = revision as u32;
    if not control_is_reproducible(wanted) {
        return 4;
    }
    const rows = control_contract(wanted);
    if rows.len() > max_declared_controls {
        return 2;
    }
    var index: usize = 0;
    while index < max_declared_controls {
        if index < rows.len() {
            write_descriptor(controls as! usize, index, rows[index]);
        } else {
            write_descriptor(controls as! usize, index, placeholder_contract()[0]);
        }
        index = index + 1;
    }
    const revisions_to_write = reproducible_revisions();
    if revisions_to_write.len() > max_reproducible_revisions {
        return 2;
    }
    var revision_index: usize = 0;
    while revision_index < max_reproducible_revisions {
        if revision_index < revisions_to_write.len() {
            unchecked {
                *(((revisions as! usize) + revision_index * 4) as! *u32) = revisions_to_write[revision_index] as u32;
            }
        } else {
            unchecked {
                *(((revisions as! usize) + revision_index * 4) as! *u32) = 0;
            }
        }
        revision_index = revision_index + 1;
    }
    unchecked {
        *(control_count as! *u32) = rows.len() as u32;
        *(contract_version as! *u32) = control_contract_version as u32;
        *(reproducible_count as! *u32) = revisions_to_write.len() as u32;
    }
    return 0;
}

// Resolve one control named in borrowed C bytes against a pinned contract revision. The status is
// one of the edit codes above; `domain_index`, `min`, and `max` describe the value range the scope
// and mode resolved to. Hosts quote bounds from this report, never from a table of their own.
pub fn control_admission(name: *const u8, name_len: usize, local: bool, mode: u32, value: f64, revision: u32): ControlAdmission {
    if value - value != 0.0 {
        return {
            found: false,
            scope: 0,
            status: edit_non_finite,
            domain_index: 0,
            min: 0.0,
            max: 0.0
        };
    }
    if not control_is_reproducible(revision) {
        return {
            found: false,
            scope: 0,
            status: edit_revision_unreproducible,
            domain_index: 0,
            min: 0.0,
            max: 0.0
        };
    }
    const rows = control_contract(revision);
    var index: usize = 0;
    while index < rows.len() {
        if name_is_named(name, name_len, rows[index].name) {
            return admit_domain(rows[index], local, mode, value);
        }
        index = index + 1;
    }
    return {
        found: false,
        scope: 0,
        status: edit_unknown_control,
        domain_index: 0,
        min: 0.0,
        max: 0.0
    };
}

// The value range one located control admits for one scope and mode.
fn admit_domain(entry: ControlContractEntry, local: bool, mode: u32, value: f64): ControlAdmission {
    var scope: u32 = scope_global;
    if local {
        scope = scope_local;
    }
    if entry.scope != scope_both and entry.scope != scope {
        return {
            found: true,
            scope: entry.scope,
            status: edit_scope_mismatch,
            domain_index: 0,
            min: 0.0,
            max: 0.0
        };
    }
    var domain_index: usize = 0;
    while domain_index < entry.domain_count as usize {
        const declared = domain_at(entry, domain_index);
        if declared.mode == mode and (declared.scope == scope or declared.scope == scope_both) {
            if value < declared.min or value > declared.max {
                return {
                    found: true,
                    scope: entry.scope,
                    status: edit_out_of_range,
                    domain_index: domain_index,
                    min: declared.min,
                    max: declared.max
                };
            }
            return {
                found: true,
                scope: entry.scope,
                status: edit_ok,
                domain_index: domain_index,
                min: declared.min,
                max: declared.max
            };
        }
        domain_index = domain_index + 1;
    }
    return {
        found: true,
        scope: entry.scope,
        status: edit_mode_unavailable,
        domain_index: 0,
        min: 0.0,
        max: 0.0
    };
}

// Decide whether one adjustment is admissible under a pinned contract revision. Status codes are
// the edit-validation codes above.
fn validate_develop_edit(
    control_name: *const u8,
    control_name_len: usize,
    mode: u32,
    value: f64,
    local: i32,
    revision: i32
): i32 {
    const name_len = control_name_len as usize;
    if name_len == 0 or name_len > control_name_bytes {
        return edit_transport as i32;
    }
    const wanted = revision as u32;
    if not control_is_reproducible(wanted) {
        return edit_revision_unreproducible as i32;
    }
    if value - value != 0.0 {
        return edit_non_finite as i32;
    }
    const rows = control_contract(wanted);
    var index: usize = 0;
    while index < rows.len() {
        if name_is_named(control_name, name_len, rows[index].name) {
            return decide_control(rows[index], mode as u32, value as f64, local != 0) as i32;
        }
        index = index + 1;
    }
    var stage: usize = 0;
    const stages = develop_stage_manifest.declared_stages();
    while stage < stages.len() {
        if name_is_named(control_name, name_len, stages[stage].name) {
            return edit_declared_stage as i32;
        }
        stage = stage + 1;
    }
    return edit_unknown_control as i32;
}

// Report, for every control row of the current contract, how far this build executes it. The
// caller supplies no control names and no stage order; it reads the core's own composition.
// Each slot is one control's bitset: 1 a composed stage drives it, 2 that stage takes develop-edit
// values, 4 it accepts a delta, 8 it accepts a target. Slots past the declared rows are zero.
// Status: 0 success, 2 limit, 3 shape.
fn describe_control_execution(
    has_camera_matrix: i32,
    editable_white_balance: i32,
    controls: *u32,
    controls_len: usize
): i32 {
    if controls_len as usize != max_declared_controls {
        return 3;
    }
    const rows = control_contract(current_contract_revision());
    if rows.len() > max_declared_controls {
        return 2;
    }
    var index: usize = 0;
    while index < max_declared_controls {
        var bits: u32 = 0;
        if index < rows.len() {
            bits = control_execution(rows[index].name, has_camera_matrix != 0, editable_white_balance != 0);
        }
        unchecked {
            *(((controls as! usize) + index * 4) as! *u32) = bits as u32;
        }
        index = index + 1;
    }
    return 0;
}
