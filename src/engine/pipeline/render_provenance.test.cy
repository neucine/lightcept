import .engine.pipeline.render_provenance;
import .engine.pipeline.stage_manifest;

// Struct values are not comparable in Cyna, so identity is asserted field by field.
fn same_row(a: render_provenance.RenderProvenanceRow, b: render_provenance.RenderProvenanceRow): bool {
    return a.stage == b.stage and a.algorithm == b.algorithm and a.version == b.version and a.asset == b.asset;
}

// The render order is part of the pinned contract, so the assertions name positions directly.
// Without a highlight stage the pass runs twelve stages; with one it runs thirteen.
test "each qualified family states its ordered render identity" {
    const dng = render_provenance.render_provenance(1, 1, 0, 0);
    assert(dng.len() == 12);
    assert(dng[0].stage == "pipeline-source");
    assert(dng[0].algorithm == "cyna-rust-pinned");
    assert(dng[0].asset == 1);
    assert(dng[1].stage == "container");
    assert(dng[2].stage == "decode");
    assert(dng[3].stage == "sensor");
    assert(dng[4].stage == "demosaic");
    assert(dng[5].stage == "profile");
    assert(dng[6].stage == "white-balance");
    assert(dng[7].stage == "working");
    assert(dng[8].stage == "exposure");
    assert(dng[9].stage == "orientation");
    assert(dng[10].stage == "resample");
    assert(dng[11].stage == "output");

    var index: usize = 0;
    while index < dng.len() {
        assert(dng[index].version > 0);
        assert(dng[index].algorithm.len() > 0 and dng[index].algorithm.len() <= render_provenance.provenance_algorithm_bytes);
        assert(dng[index].asset <= 5);
        index = index + 1;
    }

    const nef = render_provenance.render_provenance(2, 2, 0, 0);
    assert(nef.len() == 12);
    assert(nef[2].algorithm == "nikon-lossless-huffman-predictor");
    assert(nef[5].asset == 2);
    assert(nef[6].algorithm == "nikon-maker-note-as-shot-rgb");

    const unqualified = render_provenance.render_provenance(3, 1, 0, 0);
    assert(unqualified.len() == 0);
}

test "the diagnostic reconstruction choices change only their own rows" {
    const bilinear = render_provenance.render_provenance(1, 1, 0, 0);
    const malvar = render_provenance.render_provenance(1, 2, 0, 0);
    assert(bilinear.len() == malvar.len());
    assert(malvar[4].algorithm == "malvar-he-cutler-bayer");
    assert(malvar[4].version == 2);
    assert(same_row(malvar[0], bilinear[0]));
    assert(same_row(malvar[1], bilinear[1]));
    assert(same_row(malvar[3], bilinear[3]));

    const hamilton = render_provenance.render_provenance(1, 3, 0, 0);
    assert(hamilton[4].algorithm == "hamilton-adams-bayer");
    assert(hamilton[4].version == 3);

    // A highlight stage only appears when the pass runs one, and only the headroom variant
    // changes how the sensor stage is characterised.
    const plain = render_provenance.render_provenance(1, 2, 0, 0);
    assert(plain[5].stage == "profile");
    const neutral = render_provenance.render_provenance(1, 2, 1, 0);
    assert(neutral.len() == plain.len() + 1);
    assert(neutral[5].stage == "highlight");
    assert(neutral[5].algorithm == "neutral-ratio-single-channel");
    assert(same_row(neutral[3], plain[3]));
    const headroom = render_provenance.render_provenance(1, 2, 5, 0);
    assert(headroom[3].algorithm == "dng-active-area-black-white-retained-headroom");
    assert(headroom[3].version == 2);
    assert(headroom[5].algorithm == "spatial-camera-highlight-reconstruction");
}

test "the render pass names every develop capability with the contract's stage name" {
    const rows = render_provenance.render_provenance(1, 1, 0, 0);
    const contract = stage_manifest.declared_stages();
    // Steps that carry no edit (container, decode, sensor, demosaic, resample, output) name the
    // render identity, not a develop capability. A step that is a develop capability must appear
    // in the contract under the same name so one stage keeps one identity across both tables.
    var index: usize = 0;
    var shared: usize = 0;
    while index < rows.len() {
        var found: usize = 0;
        var probe: usize = 0;
        while probe < contract.len() {
            if contract[probe].name == rows[index].stage {
                found = found + 1;
            }
            probe = probe + 1;
        }
        if found > 0 {
            shared = shared + 1;
        }
        index = index + 1;
    }
    assert(shared == 3); // exposure, orientation, profile
    var check: usize = 0;
    while check < rows.len() {
        if rows[check].stage == "output" {
            var probe: usize = 0;
            var hits: usize = 0;
            while probe < contract.len() {
                if contract[probe].name == "output" {
                    hits = hits + 1;
                }
                probe = probe + 1;
            }
            assert(hits == 0); // the encode step is a render stage, not an edit capability
        }
        check = check + 1;
    }
}

test "the core names the storage variant a pass is pinned to" {
    assert(render_provenance.storage_variant_label(1, 14) == "dng/classic-le/sof3-bayer-14bit/v1");
    assert(render_provenance.storage_variant_label(1, 16) == "dng/classic-le/sof3-bayer-16bit/v1");
    assert(render_provenance.storage_variant_label(2, 14) == "nef/nikon-z8/classic-le/lossless-bayer-14bit/v1");
    assert(render_provenance.storage_variant_label(1, 11) == "");
    assert(render_provenance.storage_variant_label(2, 12) == "");
}

test "the white-balance stage carries the identity of the selected white" {
    const as_shot = render_provenance.render_provenance(1, 2, 0, 0);
    assert(as_shot[6].algorithm == "dng-as-shot-neutral");
    assert(as_shot[6].version == 1);
    assert(as_shot[6].asset == 3);
    const selected = render_provenance.render_provenance(1, 2, 0, 1);
    assert(selected.len() == as_shot.len());
    assert(selected[6].algorithm == "kim-mired-duv-bradford");
    assert(selected[6].version == 2);
    assert(selected[6].asset == 5);
    assert(same_row(selected[0], as_shot[0]));
    assert(same_row(selected[5], as_shot[5]));

    // A Z8 pass has no temperature-tint white selection, and an unqualified mode reports nothing.
    const z8_selected = render_provenance.render_provenance(2, 2, 0, 1);
    assert(z8_selected.len() == 0);
    const unknown_mode = render_provenance.render_provenance(1, 2, 0, 2);
    assert(unknown_mode.len() == 0);
}

test "staged contrast provenance places the working stages after resampling" {
    const dng = render_provenance.diagnostic_contrast_provenance(1, 1, 0, 0);
    assert(dng.len() == 15);
    assert(dng[7].stage == "working");
    assert(dng[8].stage == "orientation");
    assert(dng[9].stage == "resample");
    assert(dng[10].stage == "exposure");
    assert(dng[11].stage == "working-white");
    assert(dng[12].stage == "contrast");
    assert(dng[12].algorithm == "scene-linear-luminance-affine");
    assert(dng[12].asset == 6);
    assert(dng[13].stage == "linear-chroma");
    assert(dng[14].stage == "output");
    assert(dng[14].asset == 4);
    const with_highlight = render_provenance.diagnostic_contrast_provenance(1, 2, 5, 0);
    assert(with_highlight.len() == 16);
    const nef = render_provenance.diagnostic_contrast_provenance(2, 2, 0, 0);
    assert(nef.len() == 15);
    assert(nef[10].algorithm == "user-ev");
    assert(render_provenance.diagnostic_contrast_provenance(2, 2, 0, 1).len() == 0);
}
