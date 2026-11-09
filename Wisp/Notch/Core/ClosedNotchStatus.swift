/// Which status the closed notch shows. A tab that is switched off stays quiet; a trip is
/// on the clock, so it goes before GitHub.
enum ClosedNotchStatus {
    static func pick<Status>(trip: Status?, tripTabOn: Bool, github: Status?, githubTabOn: Bool) -> Status? {
        (tripTabOn ? trip : nil) ?? (githubTabOn ? github : nil)
    }
}
