import .engine.develop.edit_plan;
import .engine.pipeline.develop_sample;

// Diagnostic Cyna-only bounded sample batch. This is working RGB evaluation,
// not RAW decoding, output encoding, or a product renderer.
pub const algorithm_version: u32 = 1;
pub const maximum_samples: usize = 1048576;

pub struct BatchResult {
    pub valid: bool;
    // 0 success, 1 shape, 2 resource limit, 3 cancelled, 4 invalid plan/sample.
    pub status: u32;
    pub failure_index: usize;
    pub processed: usize;
}

fn failure(status: u32, index: usize, processed: usize): BatchResult {
    return {
        valid: false,
        status: status,
        failure_index: index,
        processed: processed
    };
}

// Cancellation is polled before each sample and once before output commit.
// Any failure leaves the caller's output slice unchanged. The callback must
// not mutate the input or output slices during this call.
pub fn apply(plan: edit_plan.DevelopPlan, input: []const develop_sample.SampleRgb, output: []develop_sample.SampleRgb, max_samples: usize, cancelled: (usize) => bool): BatchResult {
    if input.len() == 0 or input.len() != output.len() {
        return failure(1, 0, 0);
    }
    if max_samples == 0 or max_samples > maximum_samples or input.len() > max_samples {
        return failure(2, 0, 0);
    }
    if not develop_sample.valid_plan(plan) {
        return failure(4, 0, 0);
    }
    var staged: [:]develop_sample.SampleRgb = [];
    var index: usize = 0;
    while index < input.len() {
        if cancelled(index) {
            return failure(3, index, index);
        }
        const result = develop_sample.apply(plan, input[index]);
        if not result.valid {
            return failure(4, index, index);
        }
        staged.push(result.pixel);
        index = index + 1;
    }
    if cancelled(input.len()) {
        return failure(3, input.len(), input.len());
    }
    index = 0;
    while index < staged.len() {
        output[index] = staged[index];
        index = index + 1;
    }
    return {
        valid: true,
        status: 0,
        failure_index: input.len(),
        processed: input.len()
    };
}
