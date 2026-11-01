import .engine.color.dng_color;
import .engine.color.temperature_tint;
import { DngStatus } from .engine.core.camera_contract;

// DNG ColorMatrix camera characterization for three-channel profiles.
// Matrices are row-major. The result maps linear, black-subtracted camera RGB
// to XYZ D50; no display encoding or exposure is applied here.
// This product includes DNG technology under license by Adobe.

struct Matrix {
    values: [9]f64;
    valid: bool;
}

pub fn camera_to_working(matrix: [9]f64, red: f64, green: f64, blue: f64): dng_color.WorkingRgb {
    const xyz = product(matrix, [red, green, blue]);
    return dng_color.xyz_d50_to_working(xyz[0], xyz[1], xyz[2]);
}

fn inverse(matrix: [9]f64): Matrix {
    const a = matrix[0];
    const b = matrix[1];
    const c = matrix[2];
    const d = matrix[3];
    const e = matrix[4];
    const f = matrix[5];
    const g = matrix[6];
    const h = matrix[7];
    const i = matrix[8];
    const cofactors: [9]f64 = [
        e * i - f * h, c * h - b * i, b * f - c * e,
        f * g - d * i, a * i - c * g, c * d - a * f,
        d * h - e * g, b * g - a * h, a * e - b * d
    ];
    const determinant = a * cofactors[0] + b * cofactors[3] + c * cofactors[6];
    if determinant < 0.0000000001 and determinant > -0.0000000001 {
        return {
            values: [0.0] ** 9,
            valid: false
        };
    }
    var result: [9]f64 = [0.0] ** 9;
    var index: usize = 0;
    while index < 9 {
        result[index] = cofactors[index] / determinant;
        index = index + 1;
    }
    return {
        values: result,
        valid: true
    };
}

fn product(matrix: [9]f64, vector: [3]f64): [3]f64 {
    return [
        matrix[0] * vector[0] + matrix[1] * vector[1] + matrix[2] * vector[2],
        matrix[3] * vector[0] + matrix[4] * vector[1] + matrix[5] * vector[2],
        matrix[6] * vector[0] + matrix[7] * vector[1] + matrix[8] * vector[2]
    ];
}

fn multiply(left: [9]f64, right: [9]f64): [9]f64 {
    var result: [9]f64 = [0.0] ** 9;
    var row: usize = 0;
    while row < 3 {
        var column: usize = 0;
        while column < 3 {
            var sum: f64 = 0.0;
            var inner: usize = 0;
            while inner < 3 {
                sum = sum + left[row * 3 + inner] * right[inner * 3 + column];
                inner = inner + 1;
            }
            result[row * 3 + column] = sum;
            column = column + 1;
        }
        row = row + 1;
    }
    return result;
}

fn xy_from_xyz(xyz: [3]f64): [2]f64 {
    const total = xyz[0] + xyz[1] + xyz[2];
    if total <= 0.0 {
        return [0.0, 0.0];
    }
    return [xyz[0] / total, xyz[1] / total];
}

fn xyz_from_xy(xy: [2]f64): [3]f64 {
    return [xy[0] / xy[1], 1.0, (1.0 - xy[0] - xy[1]) / xy[1]];
}

// McCamy's xy-to-CCT approximation supplies the interpolation coordinate.
// The DNG profile weights are linear in inverse correlated temperature.
fn correlated_temperature(xy: [2]f64): f64 {
    const denominator = xy[1] - 0.1858;
    if denominator < 0.000001 and denominator > -0.000001 {
        return 0.0;
    }
    const n = (xy[0] - 0.3320) / denominator;
    return -449.0 * n * n * n + 3525.0 * n * n - 6823.3 * n + 5520.33;
}

fn illuminant_temperature(tag: u32): f64 {
    if tag == 17 {
        return 2856.0; // CIE Standard Illuminant A
    }
    if tag == 21 {
        return 6504.0; // CIE Standard Illuminant D65
    }
    return 0.0;
}

fn interpolation_weight(temperature: f64, first: f64, second: f64): f64 {
    if temperature <= first {
        return 1.0;
    }
    if temperature >= second {
        return 0.0;
    }
    return (1.0 / temperature - 1.0 / second) / (1.0 / first - 1.0 / second);
}

fn interpolated_matrix(first: [9]f64, second: [9]f64, weight: f64): [9]f64 {
    var result: [9]f64 = [0.0] ** 9;
    var index: usize = 0;
    while index < 9 {
        result[index] = weight * first[index] + (1.0 - weight) * second[index];
        index = index + 1;
    }
    return result;
}

fn bradford_to_d50(source_xy: [2]f64): Matrix {
    const bradford: [9]f64 = [
        0.8951, 0.2664, -0.1614,
        -0.7502, 1.7135, 0.0367,
        0.0389, -0.0685, 1.0296
    ];
    const inverse_bradford = inverse(bradford);
    if not inverse_bradford.valid {
        return inverse_bradford;
    }
    const source = product(bradford, xyz_from_xy(source_xy));
    const target = product(bradford, xyz_from_xy([0.34567, 0.35850]));
    var index: usize = 0;
    while index < 3 {
        if source[index] <= 0.0 or target[index] <= 0.0 {
            return {
                values: [0.0] ** 9,
                valid: false
            };
        }
        index = index + 1;
    }
    const scale: [9]f64 = [target[0] / source[0], 0.0, 0.0, 0.0, target[1] / source[1], 0.0, 0.0, 0.0, target[2] / source[2]];
    return {
        values: multiply(multiply(inverse_bradford.values, scale), bradford),
        valid: true
    };
}

// Input: 9 ColorMatrix1, 9 ColorMatrix2, 3 AsShotNeutral, 2 EXIF
// illuminant tags. Output: 9 camera-to-XYZ-D50 values, white xy, as-shot CCT,
// and first-matrix weight. Status 2 means unsupported or invalid profile.
pub export c("lc_cyna_img_v1_derive_dng_color_matrix") fn derive(input: *const c_double, input_len: c_size_t, output: *c_double, output_len: c_size_t): c_int {
    return derive_mode(input, input_len, output, output_len, false, 0.0, 0.0);
}

// Selected source white: Kelvin 2000..50000, tint -100..100 (Duv*3000).
export c("lc_cyna_img_v1_derive_selected_white") fn derive_selected(input: *const c_double, input_len: c_size_t, output: *c_double, output_len: c_size_t, kelvin: c_double, tint: c_double): c_int {
    return derive_mode(input, input_len, output, output_len, true, kelvin as f64, tint as f64);
}

// The editable source-white range this build accepts, in order: kelvin low, kelvin high,
// tint low, tint high. A host that stores an editable white quotes these bounds; it never
// writes its own. Tint is CIE 1960 Duv times 3000.
fn editable_white_balance_range(): [4]f64 {
    return [2000.0, 50000.0, -100.0, 100.0];
}

export c("lc_cyna_img_v1_white_balance_bounds") fn white_balance_bounds(output: *c_double, output_len: c_size_t): c_int {
    if output_len as usize != 4 {
        return DngStatus.shape_mismatch as c_int;
    }
    const range = editable_white_balance_range();
    write_double(output, 0, range[0]);
    write_double(output, 1, range[1]);
    write_double(output, 2, range[2]);
    write_double(output, 3, range[3]);
    return DngStatus.ok as c_int;
}

// Resolve an as-shot xy white to editable coordinates; no rendering changes.
export c("lc_cyna_img_v1_white_coordinates") fn white_coordinates(x: c_double, y: c_double, output: *c_double, output_len: c_size_t): c_int {
    if output_len as usize != 2 {
        return DngStatus.shape_mismatch as c_int;
    }
    if x != x or y != y or x <= 0.0 or y <= 0.0 or x + y >= 1.0 {
        return DngStatus.invalid_parameters as c_int;
    }
    const coordinates = temperature_tint.from_xy([x as f64, y as f64]);
    write_double(output, 0, coordinates[0]);
    write_double(output, 1, coordinates[1]);
    return DngStatus.ok as c_int;
}

fn derive_mode(input: *const c_double, input_len: c_size_t, output: *c_double, output_len: c_size_t, selected: bool, kelvin: f64, tint: f64): c_int {
    if selected {
        const range = editable_white_balance_range();
        if kelvin != kelvin or tint != tint or kelvin < range[0] or kelvin > range[1] or tint < range[2] or tint > range[3] {
            return DngStatus.invalid_parameters as c_int;
        }
    }
    if input_len as usize != 23 or output_len as usize != 13 {
        return DngStatus.shape_mismatch as c_int;
    }
    var first: [9]f64 = [0.0] ** 9;
    var second: [9]f64 = [0.0] ** 9;
    var index: usize = 0;
    while index < 9 {
        first[index] = read_double(input, index);
        second[index] = read_double(input, 9 + index);
        if first[index] != first[index] or second[index] != second[index] or first[index] < -16.0 or first[index] > 16.0 or second[index] < -16.0 or second[index] > 16.0 {
            return DngStatus.unsupported as c_int;
        }
        index = index + 1;
    }
    const neutral: [3]f64 = [read_double(input, 18), read_double(input, 19), read_double(input, 20)];
    if neutral[0] != neutral[0] or neutral[1] != neutral[1] or neutral[2] != neutral[2] or neutral[0] <= 0.0 or neutral[1] <= 0.0 or neutral[2] <= 0.0 or neutral[0] > 16.0 or neutral[1] > 16.0 or neutral[2] > 16.0 {
        return DngStatus.unsupported as c_int;
    }
    var first_temperature = illuminant_temperature(read_double(input, 21) as u32);
    var second_temperature = illuminant_temperature(read_double(input, 22) as u32);
    if first_temperature == 0.0 or second_temperature == 0.0 or first_temperature == second_temperature {
        return DngStatus.unsupported as c_int;
    }
    if first_temperature > second_temperature {
        const saved_temperature = first_temperature;
        first_temperature = second_temperature;
        second_temperature = saved_temperature;
        const saved_matrix = first;
        first = second;
        second = saved_matrix;
    }
    var white_xy: [2]f64 = [0.34567, 0.35850];
    var temperature: f64 = 0.0;
    var weight: f64 = 0.0;
    var pass: usize = 0;
    var converged = false;
    while pass < 30 and not converged and not selected {
        temperature = correlated_temperature(white_xy);
        if temperature != temperature or temperature < 1000.0 or temperature > 50000.0 {
            return DngStatus.unsupported as c_int;
        }
        weight = interpolation_weight(temperature, first_temperature, second_temperature);
        const camera_to_xyz = inverse(interpolated_matrix(first, second, weight));
        if not camera_to_xyz.valid {
            return DngStatus.unsupported as c_int;
        }
        const next = xy_from_xyz(product(camera_to_xyz.values, neutral));
        if next[0] != next[0] or next[1] != next[1] or next[0] <= 0.0 or next[1] <= 0.0 or next[0] + next[1] >= 1.0 {
            return DngStatus.unsupported as c_int;
        }
        const difference_x = next[0] - white_xy[0];
        const difference_y = next[1] - white_xy[1];
        white_xy = next;
        if difference_x < 0.0000001 and difference_x > -0.0000001 and difference_y < 0.0000001 and difference_y > -0.0000001 {
            converged = true;
        }
        pass = pass + 1;
    }
    if not converged and not selected {
        return DngStatus.unsupported as c_int;
    }
    temperature = correlated_temperature(white_xy);
    if selected {
        white_xy = temperature_tint.to_xy(kelvin, tint);
        temperature = kelvin;
        if white_xy[0] <= 0.0 or white_xy[1] <= 0.0 or white_xy[0] + white_xy[1] >= 1.0 {
            return DngStatus.invalid_parameters as c_int;
        }
    }
    weight = interpolation_weight(temperature, first_temperature, second_temperature);
    const camera_to_xyz = inverse(interpolated_matrix(first, second, weight));
    const adaptation = bradford_to_d50(white_xy);
    if not camera_to_xyz.valid or not adaptation.valid {
        return DngStatus.unsupported as c_int;
    }
    const result = multiply(adaptation.values, camera_to_xyz.values);
    index = 0;
    while index < 9 {
        write_double(output, index, result[index]);
        index = index + 1;
    }
    write_double(output, 9, white_xy[0]);
    write_double(output, 10, white_xy[1]);
    write_double(output, 11, temperature);
    write_double(output, 12, weight);
    return DngStatus.ok as c_int;
}

fn read_double(input: *const c_double, index: usize): f64 {
    unchecked {
        return *(((input as! usize) + index * 8) as! *const c_double) as f64;
    }
}

fn write_double(output: *c_double, index: usize, value: f64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *c_double) = value as c_double;
    }
}
