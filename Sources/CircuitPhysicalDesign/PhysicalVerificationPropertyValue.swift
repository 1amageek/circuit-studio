func propertyValue(in properties: [String: String], keys: [String]) -> String? {
    for key in keys {
        if let value = properties[key], !value.isEmpty {
            return value
        }
    }
    return nil
}
