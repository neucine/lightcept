import .engine.develop.crop;
import .engine.develop.straighten;
import .engine.develop.orthogonal_transform;

// User geometry is expressed on the upright source canvas, after camera
// orientation and before any fitted preview resize. Straighten retains that
// canvas extent; crop then selects an integer rectangle on it.
pub const algorithm_version: u32 = 1;

pub struct Recipe {
    pub version: u32;
    pub straighten: straighten.StraightenAsset;
    pub crop: crop.CropRect;
}

// V2 order: fixed-canvas straighten, exact quarter turn/mirror, then crop in
// the transformed canvas. V1 stays available for saved schema-7 projects.
pub struct RecipeV2 {
    pub version: u32;
    pub straighten: straighten.StraightenAsset;
    pub transform: orthogonal_transform.Transform;
    pub crop: crop.CropRect;
}

pub struct MappedPoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

pub fn neutral(width: usize, height: usize): Recipe {
    return {
        version: algorithm_version,
        straighten: {
            version: straighten.algorithm_version,
            angle_radians: 0.0,
            boundary_fill: [0.0, 0.0, 0.0]
        },
        crop: {
            version: crop.algorithm_version,
            left: 0,
            top: 0,
            width: width,
            height: height
        }
    };
}

pub fn valid(recipe: Recipe, source_width: usize, source_height: usize): bool {
    return recipe.version == algorithm_version
    and straighten.valid(recipe.straighten)
    and crop.valid(recipe.crop, source_width, source_height);
}

pub fn valid_v2(recipe: RecipeV2, source_width: usize, source_height: usize): bool {
    const shape = orthogonal_transform.extent(recipe.transform,
        source_width, source_height
    );
    return recipe.version == 2 and straighten.valid(recipe.straighten)
    and shape.status == 0
    and crop.valid(recipe.crop, shape.width, shape.height);
}

pub fn map_source_point_v2(recipe: RecipeV2, source_width: usize,
    source_height: usize, x: f64, y: f64
): MappedPoint {
    if not valid_v2(recipe, source_width, source_height) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const rotated = straighten.map_source_point(source_width, source_height,
        recipe.straighten, x, y
    );
    if not rotated.inside {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const transformed = orthogonal_transform.map_source_point(recipe.transform,
        source_width, source_height, rotated.x, rotated.y
    );
    if not transformed.inside {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const shape = orthogonal_transform.extent(recipe.transform,
        source_width, source_height
    );
    const selected = crop.map_source_point(recipe.crop, shape.width,
        shape.height, transformed.x, transformed.y
    );
    return {
        x: selected.x,
        y: selected.y,
        inside: selected.inside
    };
}

// A source point is first rotated clockwise in upright image coordinates,
// then translated into the crop. An outside point cannot anchor a retained
// source-coordinate mask; the caller must remap or invalidate that mask.
pub fn map_source_point(recipe: Recipe, source_width: usize,
    source_height: usize, x: f64, y: f64
): MappedPoint {
    if not valid(recipe, source_width, source_height) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const rotated = straighten.map_source_point(source_width, source_height,
        recipe.straighten, x, y
    );
    if not rotated.inside {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const selected = crop.map_source_point(recipe.crop, source_width,
        source_height, rotated.x, rotated.y
    );
    return {
        x: selected.x,
        y: selected.y,
        inside: selected.inside
    };
}
