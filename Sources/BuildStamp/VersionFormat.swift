public enum BuildStamp {
    public static func versionLine(productName: String, verbose: Bool) -> String {
        let shaDisplay = verbose
            ? BuildStampInfo.commitSHA
            : String(BuildStampInfo.commitSHA.prefix(7))
        return "\(productName) \(BuildStampInfo.version) (\(shaDisplay), built \(BuildStampInfo.buildTimestamp))"
    }
}
