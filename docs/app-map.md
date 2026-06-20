# App Map (user-facing view states)

Illustrative maps of the screens a user moves through and the actions that
move them. Nodes are views, arrows are transitions, labels are the user
action (with the relevant `controller#action` where it helps). These are
sketches for orientation, not a formal spec — the code is the source of truth.

One diagram per flow keeps each readable.

## Top-level navigation (signed in)

```mermaid
flowchart LR
    Status[Status]
    Feeds[Feeds]
    Posts[Posts]
    Admin[Admin Panel]
    Dev[Dev Tools]

    Settings[Settings]
    Tokens[Freefeed Access Tokens]
    Creds[AI Credentials]
    Invites[Invites]

    Status -->|Feeds| Feeds
    Status -->|Posts| Posts
    Status -->|Admin Panel*| Admin
    Status -->|Dev Tools*| Dev

    Status -.user menu.-> Settings
    Status -.user menu.-> Tokens
    Status -.user menu.-> Creds
    Status -.user menu.-> Invites
    Status -.user menu.-> SignOut[Sign Out]

    SignOut -->|session destroyed| Landing[Landing]
```

`*` Admin Panel and Dev Tools appear only for users with the matching
permission. The four user-menu items live behind the avatar dropdown.

## Authentication & registration

```mermaid
flowchart TD
    Landing[Landing] -->|Sign In| SignIn[Sign In]

    SignIn -->|submit credentials| Home[Status / Feeds]
    SignIn -->|Forgot password?| PwNew[Request reset]
    SignIn -->|Resend confirmation| ConfNew[Resend confirmation]

    PwNew -->|submit email| PwSent[(reset email sent)]
    PwSent -->|open email link| PwEdit[Set new password]
    PwEdit -->|submit| SignIn

    Register[Register] -->|submit| ConfPending[Confirmation pending]
    ConfPending -->|open email link| EmailConfirmed[(account activated)]
    EmailConfirmed --> SignIn

    ConfNew -->|submit email| ConfPending
```

## Smart feed creation

The central flow. The "new feed" page starts as a single input box and
progressively expands as the feed is identified and previewed.

```mermaid
flowchart TD
    FeedsIndex[Feeds list] -->|Add feed| NewCollapsed[New feed: input box]

    NewCollapsed -->|enter link/handle/keywords| Identifying[Identifying… spinner]

    Identifying -->|identified| Expanded[New feed: full form + live preview]
    Identifying -->|not found / error| IdError[Identification error]
    IdError -->|try again| NewCollapsed

    subgraph preview [live preview pane]
        Processing[Preview processing…] -->|built| Ready[Preview ready]
        Processing -->|failed| PFailed[Preview failed]
    end
    Expanded -.-> preview

    Expanded -->|Save & enable| Gate{credentials needed?}
    Gate -->|needs AI credential| NewCred[Add AI credential]
    Gate -->|needs access token| NewToken[Add access token]
    Gate -->|all set| FeedShow[Feed page: enabled]

    NewCred -->|saved| FeedShow
    NewToken -->|saved| FeedShow

    Expanded -->|Save as draft| FeedDraft[Feed page: draft]
```

## Feed management

```mermaid
flowchart LR
    FeedsIndex[Feeds list] -->|open a feed| FeedShow[Feed page]

    FeedShow -->|Edit| FeedEdit[Edit feed]
    FeedEdit -->|Save| FeedShow

    FeedShow -->|Enable / Pause| FeedShow
    FeedShow -->|Refresh now| FeedShow
    FeedShow -->|Purge posts| FeedShow

    FeedShow -->|recent post| PostShow[Post]
    FeedShow -->|recent event| EventShow[Event]

    FeedShow -->|Delete| FeedsIndex
```

## Account & settings

```mermaid
flowchart TD
    Settings[Settings] -->|Change email| EmailEdit[Edit email]
    Settings -->|Change password| PwUpdate[Edit password]
    EmailEdit -->|submit| EmailConfirm[(confirm via email)]
    EmailConfirm --> Settings
    PwUpdate -->|submit| Settings

    Tokens[Access tokens] -->|Add token| TokenNew[New token]
    TokenNew -->|validated & saved| TokenShow[Token]
    Tokens -->|open| TokenShow

    Creds[AI credentials] -->|Add credential| CredNew[New credential]
    CredNew -->|validated & saved| CredShow[Credential]
    Creds -->|set default| Creds

    Invites[Invites] -->|Generate invite| Invites
```
