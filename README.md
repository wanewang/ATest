# Game

A SwiftUI iOS app displaying live match odds with real-time updates.

## Architecture

```
Game/
├── GameApp.swift                  # App entry point
├── ContentView.swift              # Root view with loading/error states
│
├── Models/
│   ├── Match.swift                # Match info (ID, teams, start time)
│   ├── MatchOdds.swift            # Odds for a match (teamA, teamB)
│   └── MatchWithOdds.swift        # Combined match + odds
│
├── Networking/
│   ├── NetworkService.swift       # Network protocol + error types
│   ├── MockNetworkService.swift   # Fake REST API returning 100 random matches
│   ├── WebSocketProvider.swift    # WebSocket protocol
│   └── MockWebSocketProvider.swift# Fake WebSocket, one item per 10-100ms, max 10/sec
│
├── DataProvider/
│   └── MatchDataProvider.swift    # Fetches /matches + /odds, merges, sorts, caches
│
├── Storage/
│   └── MatchStorage.swift         # JSON file cache for offline/resume support
│
├── ViewModels/
│   └── MatchListViewModel.swift   # Pagination, real-time odds, app lifecycle
│
├── Views/
│   ├── MatchListTableView.swift   # UITableView wrapped for SwiftUI (DiffableDataSource)
│   └── MatchTableViewCell.swift   # Cell: team names, odds with blink animation, start time
│
└── Utilities/
    └── DateFormatterProvider.swift # Shared date formatter
```

## Data Flow

1. **MatchDataProvider** checks local cache. If cached, filters expired matches and fetches fresh odds. If no cache, fetches both `/matches` and `/odds` via Combine Zip with retry.
2. **MatchListViewModel** receives sorted data, pages it (40 per page), and connects the WebSocket for live odds.
3. **MockWebSocketProvider** sends one random odds update every 10–100ms (max 10 per second).
4. **MatchListTableView** uses DiffableDataSource — only cells with changed odds get reconfigured (blink animation).
5. Every 10 seconds the current data is cached. On background: cache once and disconnect WebSocket. On foreground: reconnect and resume caching.

## Threading

All shared data (`matchDataMap`, `allMatches`, pagination state) is owned by a serial `dataQueue` in `MatchListViewModel`. The main thread only updates `@Published` properties and sends UI signals. Cell reads go through `dataQueue.sync` for a safe O(1) dictionary lookup.
