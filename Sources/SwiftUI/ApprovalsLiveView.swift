import SwiftUI

@MainActor
public struct ApprovalsLiveView: View {
    @ObservedObject var model: ObserverLiveViewModel

    public init(model: ObserverLiveViewModel) {
        self.model = model
    }

    public var body: some View {
        ObserverScreenSurface(
            topology: ObserverTopologyPreset.barelyThere.configuration
        ) {
            ScrollView {
            VStack(alignment: .leading, spacing: ObserverSpacing.x8) {
                ObserverPageIdentity("APPROVALS", subtitle: "OWNER CONTROL")

                if !model.isOwnerConfigured {
                    ownerUnavailable
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                            ObserverMetadataKey("AUTHORITY SURFACE")
                            ObserverDisplayText("PENDING FIRST")
                        }
                        Spacer()
                        Button {
                            Task { await model.refreshApprovals() }
                        } label: {
                            HStack(spacing: ObserverSpacing.x2) {
                                if model.isOwnerRefreshing {
                                    ProgressView().controlSize(.mini)
                                }
                                Text(model.isOwnerRefreshing ? "REFRESHING" : "REFRESH")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isOwnerRefreshing)
                    }

                    if let error = model.ownerErrorCode {
                        ObserverFunctionalSignal(error, tone: errorTone(error))
                    }

                    if model.ownerApprovals.isEmpty {
                        emptyPending
                    } else {
                        ForEach(model.ownerApprovals) { approval in
                            approvalCard(approval)
                        }
                    }

                    if let recent = model.ownerRecentApproval {
                        recentDecision(recent)
                    }

                    boundaryNote
                }
            }
            .padding(.horizontal, ObserverSpacing.x5)
            .padding(.top, ObserverSpacing.x4)
            .padding(.bottom, ObserverSpacing.x18)
            .observerTopologyScrollProbe()
            .observerSemanticChange(
                value: model.ownerApprovals.map(\.approvalID),
                emphasis: .structural
            )
            .observerSemanticChange(
                value: model.ownerRecentApproval?.stateVersion ?? -1,
                emphasis: .structural
            )
        }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if model.isOwnerConfigured {
                    await model.refreshApprovals()
                }
            }
        }
    }

    private var ownerUnavailable: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x4) {
            ObserverFunctionalSignal("OWNER CREDENTIAL REQUIRED", tone: .warning)
            Text("Approvals are read from the owner-control plane. Add a separate obsw_ credential in System. The obsr_ read credential cannot Allow, Deny, or Close a Session.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DenseMetadataNode([
                .init(id: "read", key: "READ PLANE", value: "obsr_ · NO MUTATION"),
                .init(id: "owner", key: "OWNER PLANE", value: "obsw_ · NOT CONFIGURED")
            ])
        }
    }

    private var emptyPending: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            ObserverMetadataKey("PENDING")
            Text("NO APPROVAL NEEDS ATTENTION")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("An empty list is not an authority claim about historical approvals. This surface only lists the current authoritative PENDING set.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, ObserverSpacing.x4)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func approvalCard(_ approval: ObserverOwnerApproval) -> some View {
        let mutation = model.ownerMutationStates[approval.approvalID] ?? .idle
        return VStack(alignment: .leading, spacing: ObserverSpacing.x4) {
            HStack(alignment: .firstTextBaseline, spacing: ObserverSpacing.x3) {
                VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
                    ObserverMetadataKey("APPROVAL REQUIRED")
                    Text(String(approval.approvalID.suffix(10)).uppercased())
                        .font(.headline.monospaced())
                }
                Spacer()
                Text("V\(approval.stateVersion)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            DenseMetadataNode([
                .init(id: "project", key: "PROJECT", value: approval.projectID),
                .init(id: "scope", key: "SCOPE", value: approval.requestedScope),
                .init(id: "action", key: "ACTION", value: approval.actionClass),
                .init(id: "effect", key: "EFFECT", value: approval.effectClass)
            ])

            HStack(alignment: .firstTextBaseline) {
                Text("SERVER EXPIRES")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date(timeIntervalSince1970: approval.expiresAt), style: .time)
                    .font(.callout.monospacedDigit().weight(.medium))
            }

            mutationStatus(mutation)
                .id(mutation.semanticMotionIdentity)
                .observerSemanticTransition(.attention)

            HStack(spacing: ObserverSpacing.x3) {
                ApprovalDecisionButton(
                    title: "DENY",
                    role: .destructive,
                    disabled: mutation.isBusy,
                    confirmationTitle: "Deny this VCW request?",
                    confirmationDetail: "This changes the authoritative approval state. It does not close any existing Session."
                ) {
                    await model.decideApproval(approval.approvalID, decision: .deny)
                }

                ApprovalDecisionButton(
                    title: "ALLOW",
                    role: nil,
                    disabled: mutation.isBusy,
                    confirmationTitle: "Allow this VCW request?",
                    confirmationDetail: "Allow changes Approval to APPROVED. It does not mint a Session. GPT must claim access afterwards."
                ) {
                    await model.decideApproval(approval.approvalID, decision: .allow)
                }
            }

            if case .outcomeUnknown = mutation {
                Button("CHECK AUTHORITATIVE STATUS") {
                    Task { await model.reconcileApproval(approval.approvalID) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, ObserverSpacing.x4)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .observerSemanticTransition(.structural)
        .observerSemanticChange(
            value: mutation.semanticMotionIdentity,
            emphasis: .attention
        )
    }

    @ViewBuilder
    private func mutationStatus(_ state: ObserverOwnerMutationState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .submitting(let decision, let attemptID):
            ObserverFunctionalSignal("\(decision.rawValue) · SUBMITTING", tone: .warning)
            Text("ATTEMPT \(String(attemptID.suffix(12)).uppercased())")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        case .conflict(let version):
            ObserverFunctionalSignal("STATE CHANGED · REVIEW AGAIN", tone: .warning)
            Text("Authoritative state was refetched at version \(version). Your previous click was not replayed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .outcomeUnknown(let decision, let attemptID):
            ObserverFunctionalSignal("OUTCOME UNKNOWN", tone: .warning)
            Text("\(decision.rawValue) response was not confirmed. Attempt \(String(attemptID.suffix(12)).uppercased()) is preserved. Check status before any retry.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .resolved(let finalState):
            ObserverFunctionalSignal(finalState, tone: .positive)
        case .failed(let code):
            ObserverFunctionalSignal(code, tone: .negative)
        }
    }

    private func recentDecision(_ approval: ObserverOwnerApproval) -> some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x3) {
            ObserverMetadataKey("RECENT AUTHORITATIVE STATE")
            HStack(alignment: .firstTextBaseline) {
                Text(approval.state)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("V\(approval.stateVersion)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            DenseMetadataNode([
                .init(id: "approval", key: "APPROVAL", value: String(approval.approvalID.suffix(10)).uppercased()),
                .init(id: "project", key: "PROJECT", value: approval.projectID),
                .init(id: "reason", key: "REASON", value: approval.reason ?? "—"),
                .init(id: "session", key: "SESSION", value: approval.sessionID.map { String($0.suffix(8)).uppercased() } ?? "NOT MINTED")
            ])
            if approval.state == "APPROVED" {
                Text("APPROVED does not mean a Session exists. GPT / SessionAccessBroker must still claim access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ObserverSpacing.x4)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .observerSemanticTransition(.structural)
    }

    private var boundaryNote: some View {
        VStack(alignment: .leading, spacing: ObserverSpacing.x2) {
            ObserverMetadataKey("BOUNDARY")
            Text("Observer is an owner-control surface, not the authority owner. No raw VCW Grant, Session handle, mint internals, or private backend job IDs are available here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, ObserverSpacing.x4)
        .overlay(alignment: .top) { Divider() }
    }

    private func errorTone(_ code: String) -> SemanticTone {
        code.contains("AUTH") || code.contains("FORBIDDEN") ? .negative : .warning
    }
}

private struct ApprovalDecisionButton: View {
    let title: String
    let role: ButtonRole?
    let disabled: Bool
    let confirmationTitle: String
    let confirmationDetail: String
    let action: () async -> Void

    @State private var confirming = false

    var body: some View {
        Button(title, role: role) {
            confirming = true
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .confirmationDialog(
            confirmationTitle,
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(title, role: role) {
                Task { await action() }
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text(confirmationDetail)
        }
    }
}
