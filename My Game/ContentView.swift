//
//  ContentView.swift
//  My Game
//
//  Created by Luiz Neto on 27/10/26.
//

import SwiftUI

struct ContentView: View {
    #if os(macOS)
    @State private var selectedTab = 0
    @Namespace private var tabAnimation
    #endif

    var body: some View {
        VStack(spacing: 0) {
            Text("Smartium\(Text("Tools").foregroundStyle(.purple))")
                .font(.title.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12)

            #if os(macOS)
            Group {
                if selectedTab == 0 {
                    ThinkingOrbsView()
                } else {
                    VoiceRingView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        macOSTabButton(title: "Thinking orbs", systemImage: "sparkles", index: 0)
                        macOSTabButton(title: "Voice ring", systemImage: "waveform.circle", index: 1)
                    }
                    .padding(4)
                    .background(
                        Capsule()
                            .fill(.purple.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .strokeBorder(.purple.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
            }
            #else
            TabView {
                Tab {
                    ThinkingOrbsView()
                } label: {
                    Image(systemName: "sparkles")
                }

                Tab {
                    VoiceRingView()
                } label: {
                    Image(systemName: "waveform.circle")
                }
            }
            .tint(.purple)
            #endif
        }
    }

    #if os(macOS)
    private func macOSTabButton(title: String, systemImage: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selectedTab = index
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : .purple)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.purple)
                        .matchedGeometryEffect(id: "selectedTabPill", in: tabAnimation)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    #endif
}

struct ThinkingOrbsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentState: OrbState = ToolSharedState.load().orbState
    #if canImport(ActivityKit) && os(iOS)
    private var liveActivityManager = LiveActivityManager.shared
    @State private var liveActivityError: String?
    @State private var isChangingLiveActivity = false
    #endif

    var body: some View {
        ZStack {
            // Centered ThinkingOrb from Libraries.dev (ThinkingOrbsKit).
            ThinkingOrb(
                state: currentState,
                size: .px64,
                displaySize: 160
            )
            .contentShape(Rectangle())
            #if !os(tvOS)
            .onTapGesture {
                advanceState()
            }
            #endif

            // Instructions, current state indicator, and Dynamic Island quick toggle at the bottom.
            VStack(spacing: 10) {
                Spacer()
                Text(currentState.label)
                    .font(.headline)
                #if os(tvOS)
                Button(action: {
                    advanceState()
                }, label: {
                    Text("Select to change the orb state!")
                })
                #else
                Text("Tap the orb to change state!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                #endif

                #if canImport(ActivityKit) && os(iOS)
                Button {
                    isChangingLiveActivity = true
                    Task {
                        defer { isChangingLiveActivity = false }
                        await liveActivityManager.toggle(
                            toolTitle: "SmartiumTools",
                            state: currentState
                        )
                        liveActivityError = liveActivityManager.lastErrorMessage
                    }
                } label: {
                    Label(
                        liveActivityManager.isRunning ? "Encerrar Ilha Dinâmica" : "Ativar na Ilha Dinâmica",
                        systemImage: liveActivityManager.isRunning ? "xmark.circle.fill" : "capsule.portrait.tophalf.filled"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(liveActivityManager.isRunning ? Color.red.opacity(0.15) : Color.purple.opacity(0.15))
                    )
                    .foregroundStyle(liveActivityManager.isRunning ? .red : .purple)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .disabled(isChangingLiveActivity)
                .alert("Atividade ao Vivo", item: $liveActivityError) { _ in
                } message: { error in
                    Text(error)
                }
                #endif
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            currentState = ToolSharedState.load().orbState
            #if canImport(ActivityKit) && os(iOS)
            liveActivityManager.syncActiveActivity()
            #endif
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .smartiumOrbStateDidChange) {
                currentState = ToolSharedState.load().orbState
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                currentState = ToolSharedState.load().orbState
                #if canImport(ActivityKit) && os(iOS)
                liveActivityManager.syncActiveActivity()
                #endif
            }
        }
    }

    /// Advances the ThinkingOrb to the next available state and syncs Widgets + Dynamic Island.
    private func advanceState() {
        let allStates = OrbState.allCases
        guard let index = allStates.firstIndex(of: currentState) else { return }
        let nextIndex = (index + 1) % allStates.count
        let nextState = allStates[nextIndex]
        currentState = nextState

        ToolSharedState.updateOrbState(nextState)

        #if canImport(ActivityKit) && os(iOS)
        Task {
            await liveActivityManager.update(state: nextState)
        }
        #endif
    }
}

struct VoiceRingView: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
