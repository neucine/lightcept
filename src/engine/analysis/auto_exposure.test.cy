import .engine.analysis.auto_exposure;
import .engine.develop.edit_plan;
import .engine.pipeline.develop_sample;

test "median histogram proposal becomes a pinned exposure edit" {
    var counts: [258]u64 = [0] ** 258;
    counts[129] = 100;
    const proposal = auto_exposure.propose(counts[..], 5000, 0.25);
    assert(proposal.valid and proposal.status == 0 and proposal.selected_bin == 129);
    assert(proposal.total_pixels == 100 and proposal.version == 1);
    assert(proposal.minimum_ev < proposal.exposure_ev and proposal.exposure_ev < proposal.maximum_ev);
    assert(proposal.exposure_ev > -1.02 and proposal.exposure_ev < -0.99);
    const request = auto_exposure.exposure_request(proposal);
    assert(request.valid and request.request.id == edit_plan.edit_exposure);
    const requests: [:]edit_plan.EditRequest = [request.request];
    const compiled = edit_plan.compile(requests);
    assert(compiled.valid);
    const pixel: develop_sample.SampleRgb = {
        red: 0.5,
        green: 0.5,
        blue: 0.5
    };
    const result = develop_sample.apply(compiled.plan, pixel);
    assert(result.valid and result.pixel.red > 0.248 and result.pixel.red < 0.251);
}

test "histogram percentile selection is deterministic at both ends" {
    var counts: [258]u64 = [0] ** 258;
    counts[65] = 5;
    counts[129] = 5;
    const low = auto_exposure.propose(counts[..], 0, 0.18);
    const high = auto_exposure.propose(counts[..], 10000, 0.18);
    assert(low.valid and low.selected_bin == 65);
    assert(high.valid and high.selected_bin == 129);
}

test "censored and invalid histograms fail before producing an edit" {
    var counts: [258]u64 = [0] ** 258;
    const empty = auto_exposure.propose(counts[..], 5000, 0.18);
    assert(not empty.valid and empty.status == 4);
    assert(not auto_exposure.exposure_request(empty).valid);
    counts[257] = 10;
    const high = auto_exposure.propose(counts[..], 5000, 0.18);
    assert(not high.valid and high.status == 3);
    counts[257] = 0;
    counts[1] = 10;
    const near_zero = auto_exposure.propose(counts[..], 5000, 0.18);
    assert(not near_zero.valid and near_zero.status == 3);
    counts[1] = 0;
    counts[129] = auto_exposure.maximum_pixels + 1;
    const overflow = auto_exposure.propose(counts[..], 5000, 0.18);
    assert(not overflow.valid and overflow.status == 2);
    const bad_shape: [2]u64 = [1, 2];
    const shape = auto_exposure.propose(bad_shape[..], 5000, 0.18);
    assert(not shape.valid and shape.status == 1);
}
