import SwiftUI
import AVFoundation

// MARK: - App Entry Point
@main
struct ChromaMergeApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.themeManager.colorScheme)
        }
    }
}

// MARK: - App State (Singleton)
final class AppState: ObservableObject {
    @Published var themeManager = ThemeManager()
    @Published var audioManager = AudioManager()
    @Published var gameData = GameData()
    @Published var isFirstLaunch: Bool {
        didSet {
            UserDefaults.standard.set(isFirstLaunch, forKey: "isFirstLaunch")
        }
    }
    
    init() {
        self.isFirstLaunch = UserDefaults.standard.object(forKey: "isFirstLaunch") as? Bool ?? true
    }
}

// MARK: - Data Models
final class GameData: ObservableObject {
    @Published var highScore: Int {
        didSet {
            UserDefaults.standard.set(highScore, forKey: "highScore")
            if highScore > 0 {
                GameCenterManager.shared.submitScore(highScore)
            }
        }
    }
    
    @Published var gamesPlayed: Int {
        didSet {
            UserDefaults.standard.set(gamesPlayed, forKey: "gamesPlayed")
        }
    }
    
    @Published var highestColorReached: Int {
        didSet {
            UserDefaults.standard.set(highestColorReached, forKey: "highestColorReached")
        }
    }
    
    init() {
        self.highScore = UserDefaults.standard.integer(forKey: "highScore")
        self.gamesPlayed = UserDefaults.standard.integer(forKey: "gamesPlayed")
        self.highestColorReached = UserDefaults.standard.integer(forKey: "highestColorReached")
    }
    
    func resetAllData() {
        highScore = 0
        gamesPlayed = 0
        highestColorReached = 0
    }
}

// MARK: - Theme Manager
final class ThemeManager: ObservableObject {
    enum Theme: String, CaseIterable {
        case auto = "Automatic"
        case light = "Light"
        case dark = "Dark"
    }
    
    @Published var selectedTheme: Theme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
            updateColorScheme()
        }
    }
    
    @Published var colorScheme: ColorScheme = .dark
    
    init() {
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = Theme(rawValue: savedTheme) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .auto
        }
        updateColorScheme()
    }
    
    func updateColorScheme() {
        switch selectedTheme {
        case .auto:
            colorScheme = .dark // Default for auto in playgrounds
        case .light:
            colorScheme = .light
        case .dark:
            colorScheme = .dark
        }
    }
}

// MARK: - Audio Manager
final class AudioManager: ObservableObject {
    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
        }
    }
    
    init() {
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }
    
    func play(_ sound: Sound) {
        guard soundEnabled else { return }
        
        switch sound {
        case .pop:
            AudioServicesPlaySystemSound(1103)
        case .merge:
            AudioServicesPlaySystemSound(1057)
        case .gameOver:
            AudioServicesPlaySystemSound(1022)
        case .success:
            AudioServicesPlaySystemSound(1025)
        }
    }
    
    enum Sound {
        case pop, merge, gameOver, success
    }
}

// MARK: - Game Center Manager
class GameCenterManager {
    static let shared = GameCenterManager()
    private init() {}
    
    func submitScore(_ score: Int) {
        // Implement Game Center submission in full app
        print("Submitting score to Game Center: \(score)")
    }
}

// MARK: - Main Game View
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var gameState = GameState()
    @State private var showSettings = false
    @State private var showTutorial = false
    
    var body: some View {
        ZStack {
            // Background
            appState.themeManager.colorScheme == .dark ? Color.black : Color.white
            
            // Game Content
            VStack(spacing: 0) {
                // Header
                HeaderView(
                    score: gameState.score,
                    highScore: appState.gameData.highScore,
                    nextTileValue: gameState.currentTile,
                    theme: appState.themeManager.colorScheme
                ) {
                    showSettings = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Game Board
                GameBoardView(
                    grid: $gameState.grid,
                    theme: appState.themeManager.colorScheme,
                    cellTapped: gameState.placeTile
                )
                .disabled(gameState.gameOver)
                .padding(.horizontal, 8)
                
                Spacer()
                
                // Footer
                FooterView()
            }
            
            // Game Over Overlay
            if gameState.gameOver {
                GameOverView(
                    score: gameState.score,
                    highScore: appState.gameData.highScore,
                    action: resetGame
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
                .environmentObject(appState)
        }
        .onAppear {
            if appState.isFirstLaunch {
                showTutorial = true
                appState.isFirstLaunch = false
            }
            gameState.setup(with: appState)
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView {
                showTutorial = false
                gameState.newRandomTile()
            }
        }
        .statusBar(hidden: true)
    }
    
    private func resetGame() {
        gameState.resetGame()
        appState.gameData.gamesPlayed += 1
    }
}

// MARK: - Game State
struct GameState {
    var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 8), count: 8)
    var currentTile = 1
    var score = 0
    var gameOver = false
    
    private weak var audioManager: AudioManager?
    private weak var gameData: GameData?
    
    mutating func setup(with appState: AppState) {
        self.audioManager = appState.audioManager
        self.gameData = appState.gameData
        newRandomTile()
    }
    
    mutating func placeTile(row: Int, col: Int) {
        guard grid[row][col] == 0 else { return }
        
        grid[row][col] = currentTile
        audioManager?.play(.pop)
        checkMatches(at: (row, col))
        newRandomTile()
        checkGameOver()
    }
    
    mutating func checkMatches(at position: (row: Int, col: Int)) {
        let currentValue = grid[position.row][position.col]
        var matches = [position]
        
        // Check adjacent cells
        for direction in [(-1,0), (1,0), (0,-1), (0,1)] {
            let newRow = position.row + direction.0
            let newCol = position.col + direction.1
            
            guard newRow >= 0, newRow < grid.count,
                  newCol >= 0, newCol < grid[0].count,
                  grid[newRow][newCol] == currentValue else { continue }
            
            matches.append((newRow, newCol))
        }
        
        if matches.count > 1 {
            // Clear matched cells
            for match in matches {
                grid[match.row][match.col] = 0
            }
            
            // Create merged tile
            let mergedValue = min(currentValue + 1, 7)
            grid[position.row][position.col] = mergedValue
            
            // Update score and stats
            score += matches.count * 10
            gameData?.highScore = max(gameData?.highScore ?? 0, score)
            gameData?.highestColorReached = max(gameData?.highestColorReached ?? 0, mergedValue)
            
            // Play sound
            audioManager?.play(mergedValue == 7 ? .success : .merge)
            
            // Check for chain reactions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                var mutableSelf = self
                mutableSelf.checkMatches(at: position)
                self = mutableSelf
            }
        }
    }
    
    mutating func newRandomTile() {
        // Adaptive difficulty based on games played
        let difficulty = min(Double(gameData?.gamesPlayed ?? 0) / 20.0, 0.6)
        let random = Double.random(in: 0..<1)
        
        currentTile = switch random {
        case ..<(0.6 - difficulty): Int.random(in: 1...3)    // More basic tiles early on
        case ..<(0.9 - difficulty/2): Int.random(in: 4...5)  // Medium tiles
        default: 6                                           // Advanced tiles
        }
    }
    
    mutating func checkGameOver() {
        for row in grid {
            if row.contains(0) { return }
        }
        gameOver = true
        audioManager?.play(.gameOver)
    }
    
    mutating func resetGame() {
        grid = Array(repeating: Array(repeating: 0, count: 8), count: 8)
        score = 0
        gameOver = false
        newRandomTile()
    }
}

// MARK: - UI Components

struct HeaderView: View {
    let score: Int
    let highScore: Int
    let nextTileValue: Int
    let theme: ColorScheme
    let settingsAction: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHROMA MERGE")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(theme == .dark ? .white : .black)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("SCORE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(theme == .dark ? .gray : .black.opacity(0.7))
                        Text("\(score)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(theme == .dark ? .white : .black)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("BEST")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(theme == .dark ? .gray : .black.opacity(0.7))
                        Text("\(highScore)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(theme == .dark ? .white : .black)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                NextTileView(value: nextTileValue, theme: theme)
                
                Button(action: settingsAction) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

struct NextTileView: View {
    let value: Int
    let theme: ColorScheme
    
    var body: some View {
        VStack(spacing: 2) {
            Text("NEXT")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(theme == .dark ? .gray : .black.opacity(0.7))
            
            if value > 0 {
                let colors = [
                    Color.red,
                    Color.orange,
                    Color.yellow,
                    Color.green,
                    Color.blue,
                    Color.purple,
                    theme == .dark ? .white : .black
                ]
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(colors[value-1])
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
}

struct GameBoardView: View {
    @Binding var grid: [[Int]]
    let theme: ColorScheme
    let cellTapped: (Int, Int) -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<grid.count, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<grid[row].count, id: \.self) { col in
                        GameCellView(value: grid[row][col], theme: theme) {
                            cellTapped(row, col)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme == .dark ? Color(white: 0.15) : Color(white: 0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }
}

struct GameCellView: View {
    let value: Int
    let theme: ColorScheme
    let action: () -> Void
    
    private var cellColor: Color {
        let colors = [
            Color.red,
            Color.orange,
            Color.yellow,
            Color.green,
            Color.blue,
            Color.purple,
            theme == .dark ? .white : .black
        ]
        return value > 0 ? colors[value-1] : .clear
    }
    
    private var cellBackground: Color {
        theme == .dark ? Color(white: 0.2, opacity: 0.2) : Color(white: 0.9, opacity: 0.2)
    }
    
    var body: some View {
        ZStack {
            // Cell background
            RoundedRectangle(cornerRadius: 6)
                .fill(cellBackground)
                .frame(width: 40, height: 40)
            
            // Main cell
            if value > 0 {
                RoundedRectangle(cornerRadius: 6)
                    .fill(cellColor)
                    .shadow(color: cellColor.opacity(0.4), radius: 4, x: 0, y: 4)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Image(systemName: "plus")
                    .foregroundColor(.orange.opacity(0.5))
                    .font(.system(size: 14))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct FooterView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Licensed to Curry Industry")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            
            Text("v1.0")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.bottom, 8)
    }
}

struct GameOverView: View {
    let score: Int
    let highScore: Int
    let action: () -> Void
    
    var body: some View {
        Color.black.opacity(0.8)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack(spacing: 20) {
                    Text("GAME OVER")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 8) {
                        Text("Your Score")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(score)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    if score == highScore && highScore > 0 {
                        Text("New High Score!")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    
                    Button(action: action) {
                        Text("PLAY AGAIN")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .padding()
                            .frame(width: 200)
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            )
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("APPEARANCE")) {
                    Picker("Theme", selection: $appState.themeManager.selectedTheme) {
                        ForEach(ThemeManager.Theme.allCases, id: \.self) { theme in
                            Text(theme.rawValue)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("AUDIO")) {
                    Toggle("Sound Effects", isOn: $appState.audioManager.soundEnabled)
                }
                
                Section(header: Text("GAME DATA")) {
                    HStack {
                        Text("High Score")
                        Spacer()
                        Text("\(appState.gameData.highScore)")
                    }
                    
                    HStack {
                        Text("Highest Color")
                        Spacer()
                        Text(appState.gameData.highestColorReached > 0 ? 
                             GameConfig.colorNames[appState.gameData.highestColorReached-1] : "-")
                    }
                    
                    HStack {
                        Text("Games Played")
                        Spacer()
                        Text("\(appState.gameData.gamesPlayed)")
                    }
                    
                    Button("Reset All Data", role: .destructive) {
                        appState.gameData.resetAllData()
                    }
                }
                
                Section {
                    Button("Done") {
                        isPresented = false
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TutorialView: View {
    let dismissAction: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("HOW TO PLAY")
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 10)
                    
                    TutorialStep(
                        icon: "plus.circle.fill",
                        title: "Place Tiles",
                        description: "Tap on empty cells to place your colored tile"
                    )
                    
                    TutorialStep(
                        icon: "arrow.triangle.merge",
                        title: "Merge Colors",
                        description: "When 2+ same-color tiles touch, they merge to the next color in the spectrum"
                    )
                    
                    TutorialStep(
                        icon: "sparkles",
                        title: "Color Progression",
                        description: "Red → Orange → Yellow → Green → Blue → Purple → Diamond"
                    )
                    
                    TutorialStep(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Scoring",
                        description: "Earn more points for bigger merges and reaching higher colors"
                    )
                    
                    TutorialStep(
                        icon: "hourglass",
                        title: "Game Over",
                        description: "The game ends when the grid fills up with no more moves possible"
                    )
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Let's Play!", action: dismissAction)
                }
            }
        }
    }
}

struct TutorialStep: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                
                Text(description)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Constants
struct GameConfig {
    static let colorNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Diamond"]
}