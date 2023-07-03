pub const AdvancedFeatures = packed struct(u64) {
    advanced_array_features: bool = false,
    advanced_union_features: bool = false,
    optional_scalars: bool = false,
    default_vectors_and_strings: bool = false,
    _padding: u60 = 0,
};
