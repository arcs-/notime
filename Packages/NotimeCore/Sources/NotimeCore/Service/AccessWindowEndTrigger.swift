/// Which Device Activity callback reported the end of an access window.
public enum AccessWindowEndTrigger: Sendable {
    case usageThresholdReached
    case intervalEnded
}
