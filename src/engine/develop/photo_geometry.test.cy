import .engine.develop.photo_geometry;

test "geometry recipe keeps upright source coordinates through straighten then crop" {
    var recipe = photo_geometry.neutral(5, 5);
    recipe.crop.left = 1;
    recipe.crop.top = 1;
    recipe.crop.width = 3;
    recipe.crop.height = 3;
    assert(photo_geometry.valid(recipe, 5, 5));
    const center = photo_geometry.map_source_point(recipe, 5, 5, 2.0, 2.0);
    assert(center.inside and center.x == 1.0 and center.y == 1.0);
    const outside = photo_geometry.map_source_point(recipe, 5, 5, 0.0, 0.0);
    assert(not outside.inside);
    recipe.straighten.angle_radians = 0.2;
    const rotated = photo_geometry.map_source_point(recipe, 5, 5, 3.0, 2.0);
    assert(rotated.inside and rotated.x > 1.980 and rotated.x < 1.981);
    assert(rotated.y > 1.198 and rotated.y < 1.200);
}

test "geometry recipe validates full resolution source and rejects invalid assets" {
    var recipe = photo_geometry.neutral(8256, 5504);
    assert(photo_geometry.valid(recipe, 8256, 5504));
    recipe.crop.width = 8257;
    assert(not photo_geometry.valid(recipe, 8256, 5504));
    recipe.crop.width = 8256;
    recipe.straighten.angle_radians = 0.31;
    assert(not photo_geometry.valid(recipe, 8256, 5504));
    recipe.straighten.angle_radians = 0.0;
    recipe.version = 2;
    assert(not photo_geometry.valid(recipe, 8256, 5504));
}
