import .engine.pipeline.control_contract;

// Locate a row by name so the assertions never depend on table order.
fn control_index(revision: u32, name: string): usize {
    const rows = control_contract.control_contract(revision);
    var index: usize = 0;
    while index < rows.len() {
        if rows[index].name == name {
            return index;
        }
        index = index + 1;
    }
    return rows.len();
}

test "the contract declares every control an edit recipe may carry" {
    const rows = control_contract.control_contract(2);
    assert(rows.len() == 28);
    var index: usize = 0;
    while index < rows.len() {
        const entry = rows[index];
        assert(entry.name.len() > 0 and entry.name.len() < 24);
        assert(entry.label.len() > 0 and entry.label.len() < 48);
        assert(entry.family > 0 and entry.family <= 8);
        assert(entry.scope > 0 and entry.scope <= 3);
        assert(entry.domain_count > 0 and entry.domain_count <= 4);
        var domain: usize = 0;
        while domain < entry.domain_count as usize {
            assert(control_contract.domain_at(entry, domain).min <= control_contract.domain_at(entry, domain).max);
            domain = domain + 1;
        }
        index = index + 1;
    }

    var named: [:]string = ["exposure", "temp", "tint", "blacks", "shadows", "contrast", "highlights",
        "whites", "saturation", "hue", "color_hue", "color_sat", "red_luminance", "orange_luminance",
        "yellow_luminance", "green_luminance", "aqua_luminance", "blue_luminance", "purple_luminance",
        "magenta_luminance", "noise", "moire", "defringe", "clarity", "texture", "sharpening", "dehaze",
        "amount"
    ];
    for control in named {
        assert(control_index(2, control) < 28);
    }
}

// The row order is the order the editor and the planner advertise, so a control index in an
// intent template always names the row at that position.
test "contract order is the advertised control order" {
    const rows = control_contract.control_contract(2);
    var advertised: [:]string = ["exposure", "contrast", "temp", "tint", "sharpening", "texture",
        "clarity", "dehaze", "saturation", "red_luminance", "orange_luminance", "yellow_luminance",
        "green_luminance", "aqua_luminance", "blue_luminance", "purple_luminance", "magenta_luminance",
        "highlights", "shadows", "whites", "blacks", "hue", "color_hue", "color_sat", "noise", "moire",
        "defringe", "amount"
    ];
    assert(rows.len() == advertised.len());
    var position: usize = 0;
    while position < rows.len() {
        assert(rows[position].name == advertised[position]);
        position = position + 1;
    }
    assert(rows[9].name == "red_luminance");
    assert(rows[22].name == "color_hue");
}

test "the contract decides what a control value means" {
    assert(control_contract.validate_edit("exposure", 0, 4.0, false, 2) == 0);
    assert(control_contract.validate_edit("exposure", 0, 4.5, false, 2) == 5);
    assert(control_contract.validate_edit("temp", 1, 50000.0, false, 2) == 0);
    assert(control_contract.validate_edit("temp", 1, 1999.0, false, 2) == 5);
    // Local white balance is a relative shift, not kelvin.
    assert(control_contract.validate_edit("temp", 1, 50000.0, true, 2) == 5);
    assert(control_contract.validate_edit("temp", 1, 50.0, true, 2) == 0);

    // Scope-restricted controls stay in their scope.
    assert(control_contract.validate_edit("noise", 0, 50.0, true, 2) == 0);
    assert(control_contract.validate_edit("noise", 0, 50.0, false, 2) == 3);
    assert(control_contract.validate_edit("red_luminance", 0, 50.0, true, 2) == 3);

    // A declared develop stage is not yet a control with a pinned range.
    assert(control_contract.validate_edit("tone_curve", 1, 1.0, false, 2) == 2);
    assert(control_contract.validate_edit("hsl_grading", 1, 1.0, false, 2) == 2);
    assert(control_contract.validate_edit("not_a_control", 0, 1.0, false, 2) == 1);

    // Revision 1 pins the sharpening target ceiling that older projects replay.
    assert(control_contract.validate_edit("sharpening", 1, 150.0, false, 1) == 0);
    assert(control_contract.validate_edit("sharpening", 1, 151.0, false, 1) == 5);
    assert(control_contract.validate_edit("exposure", 0, 1.0, false, 3) == 6);
    assert(control_contract.validate_edit("exposure", 0, 1.0 / 0.0, false, 2) == 7);
}

test "every reproducible revision carries its own bounds" {
    const revisions = control_contract.reproducible_revisions();
    assert(revisions.len() == 2);
    assert(revisions[0] == 1);
    assert(revisions[1] == 2);
    assert(control_contract.control_is_reproducible(1));
    assert(not control_contract.control_is_reproducible(3));

    const first = control_contract.control_contract(1);
    const current = control_contract.control_contract(2);
    assert(first.len() == current.len());
    var index: usize = 0;
    while index < current.len() {
        assert(first[index].name == current[index].name);
        assert(first[index].units == current[index].units);
        assert(first[index].scope == current[index].scope);
        assert(first[index].neutral == current[index].neutral);
        assert(first[index].domain_count == current[index].domain_count);
        var domain: usize = 0;
        while domain < current[index].domain_count as usize {
            assert(control_contract.domain_at(first[index], domain).min == control_contract.domain_at(current[index], domain).min);
            assert(control_contract.domain_at(first[index], domain).max == control_contract.domain_at(current[index], domain).max);
            domain = domain + 1;
        }
        index = index + 1;
    }
}

// The contract declares a control long before a kernel exists for it. Only the core knows which
// declared controls its composed plan runs, so the host never keeps its own exception list.
test "the core reports which declared controls its composed plan executes" {
    // Exposure is the only control every characterisation drives.
    assert(control_contract.control_execution("exposure", false, false) == 7);
    assert(control_contract.control_execution("exposure", true, true) == 7);

    // The working-white stage composes only for a characterised source with a reviewable white.
    assert(control_contract.control_execution("temp", false, false) == 0);
    assert(control_contract.control_execution("temp", false, true) == 0);
    assert(control_contract.control_execution("temp", true, true) == 15);
    // Both names in one driven list resolve, and neither matches a neighbouring token.
    assert(control_contract.control_execution("tint", true, true) == 15);

    // The chroma stage composes with a fixed neutral value: declared, not edit driven.
    assert(control_contract.control_execution("saturation", true, true) == 0);

    // Tone, detail, geometry, mask, and output controls are declared but have no composed stage.
    var deferred: [:]string = ["contrast", "highlights", "shadows", "whites", "blacks", "clarity", "texture",
        "sharpening", "dehaze", "red_luminance", "hue", "noise", "amount"
    ];
    for control in deferred {
        assert(control_contract.control_execution(control, true, true) == 0);
    }
}
