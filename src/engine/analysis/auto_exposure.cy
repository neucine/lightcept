import .engine.develop.edit_plan;

extern c("log2") fn log2(value: c_double): c_double;

// Diagnostic analysis v1 of the 258-bin signed scene-linear Rec.2020
// histogram. This proposes one exposure edit; it never mutates a plan.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: u64 = 250000000;

pub struct Proposal {
    pub valid: bool;
    // 0 success, 1 shape, 2 invalid counts/parameters, 3 censored percentile,
    // 4 empty histogram.
    pub status: u32;
    pub version: u32;
    pub exposure_ev: f64;
    pub minimum_ev: f64;
    pub maximum_ev: f64;
    pub selected_bin: usize;
    pub total_pixels: u64;
}

pub struct RequestResult {
    pub valid: bool;
    pub request: edit_plan.EditRequest;
}

fn failure(status: u32): Proposal {
    return {
        valid: false,
        status: status,
        version: algorithm_version,
        exposure_ev: 0.0,
        minimum_ev: 0.0,
        maximum_ev: 0.0,
        selected_bin: 0,
        total_pixels: 0
    };
}

fn exposure_for(target: f64, observed: f64): f64 {
    return log2((target / observed) as c_double) as f64;
}

// Percentile is in basis points, 0..10000. Target is linear reference-white
// luminance in [0.05, 0.9]. The returned interval brackets the EV implied by
// any sample in the selected bin; no within-bin distribution is assumed.
pub fn propose(counts: []const u64, percentile_basis_points: u32, target_y: f64): Proposal {
    if counts.len() != 258 {
        return failure(1);
    }
    if percentile_basis_points > 10000 or not (target_y >= 0.05 and target_y <= 0.9) {
        return failure(2);
    }
    var total: u64 = 0;
    var index: usize = 0;
    while index < 258 {
        if counts[index] > maximum_pixels - total {
            return failure(2);
        }
        total = total + counts[index];
        index = index + 1;
    }
    if total == 0 {
        return failure(4);
    }
    const rank = ((total - 1) * (percentile_basis_points as u64)) / 10000;
    var cumulative: u64 = 0;
    index = 0;
    while index < 258 and rank >= cumulative + counts[index] {
        cumulative = cumulative + counts[index];
        index = index + 1;
    }
    // Negative values, the first near-zero bin, and Y >= 1 have no bounded
    // positive-luminance interval suitable for an exposure estimate.
    if index < 2 or index > 256 {
        return failure(3);
    }
    const lower = ((index - 1) as f64) / 256.0;
    const upper = (index as f64) / 256.0;
    const middle = (lower + upper) * 0.5;
    return {
        valid: true,
        status: 0,
        version: algorithm_version,
        exposure_ev: exposure_for(target_y, middle),
        minimum_ev: exposure_for(target_y, upper),
        maximum_ev: exposure_for(target_y, lower),
        selected_bin: index,
        total_pixels: total
    };
}

pub fn exposure_request(proposal: Proposal): RequestResult {
    if not proposal.valid or proposal.status != 0 or proposal.version != algorithm_version
    or not (proposal.exposure_ev >= edit_plan.exposure_min() and proposal.exposure_ev <= edit_plan.exposure_max()) {
        return {
            valid: false,
            request: {
                id: 0,
                mode: 0,
                value: 0.0
            }
        };
    }
    return {
        valid: true,
        request: {
            id: edit_plan.edit_exposure,
            mode: edit_plan.mode_target,
            value: proposal.exposure_ev
        }
    };
}
