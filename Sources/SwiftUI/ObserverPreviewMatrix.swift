#if DEBUG
import SwiftUI

#Preview("01 RUNNING ACTIVE ONLINE") { ObserverPreviewShell(scenario: .runningActiveOnline) }
#Preview("02 STARTING ACTIVE ONLINE") { ObserverPreviewShell(scenario: .startingActiveOnline) }
#Preview("03 VERIFYING ACTIVE ONLINE") { ObserverPreviewShell(scenario: .verifyingActiveOnline) }
#Preview("04 FINALIZING ACTIVE ONLINE") { ObserverPreviewShell(scenario: .finalizingActiveOnline) }
#Preview("05 COMPLETED VERIFIED PRESENTATION UNKNOWN") { ObserverPreviewShell(scenario: .completedVerifiedPresentationUnknown) }
#Preview("06 COMPLETED PRESENTATION CONFIRMED") { ObserverPreviewShell(scenario: .completedPresentationConfirmed) }
#Preview("07 FAILED ONLINE") { ObserverPreviewShell(scenario: .failedOnline) }
#Preview("08 ABORTED") { ObserverPreviewShell(scenario: .aborted) }
#Preview("09 RESUMABLE") { ObserverPreviewShell(scenario: .resumable) }
#Preview("10 WAITING APPROVAL") { ObserverPreviewShell(scenario: .waitingApproval) }
#Preview("11 RUNNING SLOW") { ObserverPreviewShell(scenario: .runningSlow) }
#Preview("12 RUNNING STALE") { ObserverPreviewShell(scenario: .runningStale) }
#Preview("13 RUNNING SUSPECTED STUCK") { ObserverPreviewShell(scenario: .runningSuspectedStuck) }
#Preview("14 RUNNING LAST KNOWN OFFLINE") { ObserverPreviewShell(scenario: .runningLastKnownOffline) }
#Preview("15 RUNNING RECONNECTING") { ObserverPreviewShell(scenario: .runningReconnecting) }
#Preview("16 AUTH FAILED CACHED") { ObserverPreviewShell(scenario: .authFailedCached) }
#Preview("17 MULTIPLE ACTIVE AGGREGATE") { ObserverPreviewShell(scenario: .multipleActiveAggregate) }
#Preview("18 NO RUN EMPTY") { ObserverPreviewShell(scenario: .noRunEmpty) }
#endif
