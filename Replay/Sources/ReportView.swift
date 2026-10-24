import SwiftUI

struct ReportContent: View {
    let report: ReviewReport
    var onMoment: ((Double) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(report.verdictLabel, systemImage: report.verdict == "on_track" ? "checkmark.circle" : report.verdict == "cannot_assess" ? "eye.slash" : "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Palette.accent, in: Capsule()).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                }
                Text(report.headline).font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(.white)
                Text(report.summary).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)).lineSpacing(4)
                Text("\(report.confidence.capitalized) confidence · AI feedback")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 26))

            if let verification = report.verification, verification.status == "completed" {
                verificationCard(verification)
            }

            if let issues = report.issues, !issues.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What needs fixing").font(.system(size: 21, weight: .semibold)).foregroundStyle(Palette.ink)
                    ForEach(issues) { issue in issueCard(issue) }
                }.accessibilityIdentifier("issues-section")
            } else if !report.improvements.isEmpty {
                feedbackList("Suggested fixes", symbol: "arrow.up.right", items: report.improvements, color: Palette.orange)
            } else if report.verdict == "on_track" {
                Card {
                    Label("No clear problems were found in the visible work.", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(Palette.ink)
                }
            }

            if !report.strengths.isEmpty { feedbackList("What went well", symbol: "checkmark", items: report.strengths, color: Palette.ink) }

            if !report.moments.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Video moments").font(.system(size: 20, weight: .semibold)).tracking(-0.5)
                        Spacer()
                        Text("\(report.moments.count)").font(.system(size: 11, weight: .bold)).padding(7).background(Palette.line, in: Circle())
                    }.foregroundStyle(Palette.ink)
                    ForEach(report.moments) { moment in
                        Button {
                            onMoment?(moment.seconds)
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                VStack(spacing: 6) {
                                    Text(moment.seconds.clockString).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    if onMoment != nil { Image(systemName: "play.fill").font(.system(size: 9)) }
                                }.foregroundStyle(Palette.ink).frame(width: 49).padding(.vertical, 11)
                                    .background(Palette.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(moment.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                                    Text(moment.observation).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(3)
                                    if !moment.suggestion.isEmpty { Text(moment.suggestion).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink).lineSpacing(3) }
                                }
                                Spacer(minLength: 0)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).disabled(onMoment == nil)
                            .accessibilityLabel("\(moment.seconds.clockString), \(moment.title). \(moment.observation). \(moment.suggestion)")
                    }
                }
            }

            if !report.criteria.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Against your goal").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.ink)
                    Card {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(report.criteria) { criterion in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        Text(criterion.name).font(.system(size: 14, weight: .semibold))
                                        Spacer()
                                        Text(criterion.label).font(.system(size: 10, weight: .semibold)).fixedSize()
                                            .padding(.horizontal, 8).padding(.vertical, 5).background(Palette.background, in: Capsule())
                                    }.foregroundStyle(Palette.ink)
                                    Text(criterion.evidence).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(3)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Your next step", systemImage: "scope").font(.system(size: 15, weight: .semibold))
                Text(report.nextPractice).font(.system(size: 16)).lineSpacing(5)
            }.foregroundStyle(Palette.ink).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 24))

            if !report.limitations.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("A note on this review").font(.system(size: 12, weight: .semibold))
                    ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in
                        Text(limitation).font(.system(size: 12)).lineSpacing(3)
                    }
                }.foregroundStyle(Palette.muted).padding(.horizontal, 4)
            }
        }
    }

    private func verificationCard(_ verification: ReviewVerification) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Evidence rechecked", systemImage: "checkmark.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(verification.summary).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(3)
                Text("\(verification.confirmedIssueCount) of \(verification.candidateIssueCount) proposed issues retained")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                if let decisions = verification.decisions, !decisions.isEmpty {
                    DisclosureGroup("See the review checks") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(decisions) { decision in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Proposed issue \(decision.candidateIndex + 1) · \(decision.label)")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
                                    Text(decision.reason).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
                                }
                            }
                        }.padding(.top, 12)
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                }
                Text("Two AI passes reviewed the same video. Rechecking improves scrutiny; it does not guarantee correctness.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(2)
            }
        }.accessibilityIdentifier("verification-summary")
    }

    private func issueCard(_ issue: ReviewIssue) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Text(issue.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    if let seconds = issue.seconds {
                        Button { onMoment?(seconds) } label: {
                            HStack(spacing: 5) {
                                if onMoment != nil { Image(systemName: "play.fill").font(.system(size: 8)) }
                                Text(seconds.clockString).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }.foregroundStyle(Palette.ink).padding(.horizontal, 10).padding(.vertical, 9)
                                .background(Palette.accent.opacity(0.3), in: Capsule())
                        }.buttonStyle(.plain).disabled(onMoment == nil)
                            .accessibilityLabel("Jump to \(seconds.clockString): \(issue.title)")
                    }
                }
                issueDetail("What happened", text: issue.observation)
                issueDetail("Why it matters", text: issue.whyItMatters)
                VStack(alignment: .leading, spacing: 6) {
                    Label("How to fix it", systemImage: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                    Text(issue.howToFix).font(.system(size: 14)).lineSpacing(3)
                }.foregroundStyle(Palette.ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func issueDetail(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(text).font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(3)
        }
    }

    private func feedbackList(_ title: String, symbol: String, items: [String], color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 17) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ink)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                            .frame(width: 23, height: 23).background(color.opacity(0.09), in: Circle()).foregroundStyle(color)
                        Text(item).font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(3).padding(.top, 2)
                    }
                }
            }
        }
    }
}

struct ExampleReportView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("EXAMPLE REVIEW", systemImage: "info.circle")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted)
                    Text("An idea of what’s ahead.").font(.system(size: 27, weight: .semibold)).tracking(-0.8).foregroundStyle(Palette.ink)
                    Text("An example of feedback on an assembly task. Your review will focus on the work shown in your own video.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    ReportContent(report: .example)
                }.padding(22)
            }.background(Palette.background).navigationTitle("Example review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.tint(Palette.ink)
    }
}
