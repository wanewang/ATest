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
│   └── MatchDataProvider.swift    # Storage-first load, network fetch, WebSocket relay
│
├── Storage/
│   └── MatchStorage.swift         # JSON file cache for offline/resume support
│
├── ViewModels/
│   └── MatchListViewModel.swift   # Pagination, real-time odds, app lifecycle, all on dataQueue
│
├── Views/
│   ├── MatchListTableView.swift   # UITableView wrapped for SwiftUI (DiffableDataSource)
│   └── MatchTableViewCell.swift   # Cell: team names, odds with blink animation, start time
│
└── Utilities/
    └── DateFormatterProvider.swift # Shared date formatter
```

## Data Flow

1. **MatchDataProvider** loads from storage first (`fetchMatchesFromStorage`). If cached matches exist, it filters out expired ones, seeds `MockNetworkService` with the cached matches via `generateAdditionalData`, and returns them immediately. It then fetches `/matches` + `/odds` via Combine Zip with retry(5), merges and sorts by start time. On reset (pull-to-refresh), storage is cleared and `NetworkService` regenerates all data.
2. **MatchListViewModel** calls `fetchMatchesFromStorage` on `dataQueue`. If cache hits, it displays cached data instantly, then background-refreshes from network. If no cache, it fetches directly from network. All data processing (`matchDataMap`, `allMatches`, pagination) runs on `dataQueue`; only `@Published` properties update on main thread.
3. **MockWebSocketProvider** sends one random odds update every 10–100ms (max 10 per second).
4. **MatchListTableView** uses DiffableDataSource — only cells with changed odds get reconfigured (blink animation).
5. Every 10 seconds the current data is cached. On background: cache once and disconnect WebSocket. On foreground: reconnect and resume caching.

## Threading

All shared data (`matchDataMap`, `allMatches`, pagination state, `fetchCancellable`) is owned by a serial `dataQueue` in `MatchListViewModel`. Network fetches and storage loads subscribe on `dataQueue`. The main thread only updates `@Published` properties (`displayedMatchIDs`, `loadState`) and sends UI signals (`oddsUpdated`). Cell reads go through `dataQueue.sync` for a safe O(1) dictionary lookup. `MockNetworkService` emits on a background queue (`DispatchQueue.global`).
