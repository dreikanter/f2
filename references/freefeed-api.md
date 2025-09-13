# Freefeed API Reference

App tokens / Token access rights

Token access rights are defined by access scopes set. This page describes the access rights that the tokens will receive when selecting specific access scopes.

From a technical point of view, each scope corresponds to a set of API methods that the token can access.


## read-my-info

Read my user information

This access level allows to read your profile data, such as:

- Read my username, screenname, email and display preferences
- Read my profile stats such as number of likes and posts
- Read my subscriptions list
- Read my subscribers list

Allowed API methods (for developers)

GET /vN/users/whoami
GET /vN/managedGroups
GET /vN/users/blockedByMe
GET /vN/timelines/home/list


## read-my-files

Read information about my uploaded files
Allowed API methods (for developers)
GET /vN/attachments/my
GET /vN/attachments/my/stats


## read-feeds

Read feeds, including my feeds and direct messages

This access level allows to read posts and comments that you can read, such as:

- Read and search my posts and comments
- Read and search my direct and saved messages
- Read and search my Friendfeed archive
- Read and search all public posts and comments
- Read and search all private posts and comments of people and groups I'm subscribed to

Allowed API methods (for developers)
GET /vN/timelines/home
GET /vN/timelines/home/:feedId/posts
GET /vN/timelines/home/list
GET /vN/timelines/filter/discussions
GET /vN/timelines/filter/directs
GET /vN/timelines/filter/saves
GET /vN/users/getUnreadDirectsNumber
GET /vN/timelines/:username
GET /vN/timelines/:username/likes
GET /vN/timelines/:username/comments
GET /vN/search
GET /vN/summary/:days
GET /vN/summary/:username/:days
GET /vN/bestof
GET /vN/timelines-rss/:username
GET /vN/posts/:postId
GET /vN/posts/:postId/translated-body
GET /vN/posts/:postId/backlinks
GET /vN/archives/post-by-old-name/:name
GET /vN/allGroups
GET /vN/comments/:commentId/likes
GET /vN/everything
GET /vN/comments/:commentId
GET /vN/comments/:commentId/translated-body
GET /vN/posts/:postId/comments/:seqNumber
POST /vN/posts/byIds
POST /vN/comments/byIds
GET /vN/calendar/:username/:year
GET /vN/calendar/:username/:year/:month
GET /vN/calendar/:username/:year/:month/:day
GET /vN/attachments/:attId
GET /vN/attachments/:attId/:type
POST /vN/attachments/byIds


## read-users-info

Read users' information

This access level allows to read public profiles of other people and profiles of your subscriptions, such as:

- Read their usernames and screennames
- Read their subscriptions and subscribers lists

Allowed API methods (for developers)
GET /vN/users/:username
GET /vN/users/:username/statistics
GET /vN/users/:username/subscribers
GET /vN/users/:username/subscriptions
GET /vN/users/sparseMatches


## read-realtime

Read realtime messages
This access level allows to read realtime messages that you can read.
Allowed API methods (for developers)
WS *


## manage-my-files

Update my uploaded files

Allowed API methods (for developers)
POST /vN/attachments/my/sanitize


## manage-notifications

Manage notifications

This access level allows to manage your notifications, such as:

- Read notifications
- Mark notifications as read

Allowed API methods (for developers)
GET /vN/notifications
GET /vN/notifications/:notifId
POST /vN/users/markAllNotificationsAsRead
GET /vN/users/getUnreadNotificationsNumber
POST /vN/posts/:postId/notifyOfAllComments


## manage-posts

Manage (read, write and delete) posts, comments, and likes

This access level allows to manage posts and comments, such as:

- Write new posts and direct messages
- Edit your old posts and direct messages
- Write new comments
- Edit your old comments
- Like and unlike posts and comments

Allowed API methods (for developers)
GET /vN/posts/:postId
GET /vN/users/markAllDirectsAsRead
GET /vN/comments/:commentId/likes
POST /vN/attachments
POST /vN/bookmarklet
POST /vN/posts
PUT /vN/posts/:postId
POST /vN/posts/:postId/disableComments
POST /vN/posts/:postId/enableComments
DELETE /vN/posts/:postId
POST /vN/comments
PUT /vN/comments/:commentId
DELETE /vN/comments/:commentId
POST /vN/posts/:postId/like
POST /vN/posts/:postId/unlike
POST /vN/comments/:commentId/like
POST /vN/comments/:commentId/unlike
POST /vN/posts/:postId/leave
POST /vN/posts/:postId/notifyOfAllComments
POST /vN/undo/:subject


## manage-my-feeds

Manage my subscriptions, hides, bans, and saves

This access level allows to manage your subscription feed, such as:

- Subscribe to people and groups, or send subscription requests
- Unsubscribe from people or groups
- Ban and unban people
- Hide, unhide, and save posts

Allowed API methods (for developers)
POST /vN/users/:username/subscribe
PUT /vN/users/:username/subscribe
POST /vN/users/:username/unsubscribe
POST /vN/posts/:postId/hide
POST /vN/posts/:postId/unhide
POST /vN/users/:username/ban
POST /vN/users/:username/unban
POST /vN/posts/:postId/save
DELETE /vN/posts/:postId/save
POST /vN/users/:username/sendRequest
POST /vN/requests/:followedUserName/revoke
POST /vN/timelines/home
PATCH /vN/timelines/home
DELETE /vN/timelines/home/:feedId
PATCH /vN/timelines/home/:feedId
GET /vN/timelines/home/:feedId
GET /vN/timelines/home/subscriptions
PATCH /vN/timelines/home
POST /vN/groups/:groupName/disableBans
POST /vN/groups/:groupName/enableBans


## manage-profile

Manage my and my groups profiles

This access level allows to change your profile and profiles of groups that you admin, such as:

- Change my screenname, picture, description, and display preferences
- Change my feed's privacy level (public, protected, private)
- Change my groups' screenname, picture, and description
- Change my groups' privacy settings (public, protected, private)

Allowed API methods (for developers)
POST /vN/groups/:groupName/updateProfilePicture
POST /vN/users/updateProfilePicture
PUT /vN/users/:userId


## manage-groups

Manage groups

This access level allows to manage my groups, such as:

- Create new groups
- Change group admins
- Accept or reject subscription requests
- Unsubscribe people from groups

Allowed API methods (for developers)
POST /vN/groups
POST /vN/groups/:groupName/subscribers/:adminName/admin
POST /vN/groups/:groupName/subscribers/:adminName/unadmin
POST /vN/groups/:groupName/sendRequest
POST /vN/groups/:groupName/acceptRequest/:userName
POST /vN/groups/:groupName/rejectRequest/:userName
POST /vN/groups/:groupName/unsubscribeFromGroup/:userName
GET /vN/groups/:groupName/blockedUsers
POST /vN/groups/:groupName/block/:userName
POST /vN/groups/:groupName/unblock/:userName


## manage-subscription-requests

Manage subscription requests

This access level allows to manage your subscriptions and and subscription requests, such as:

- Accept or reject subscription requests
- Unsubscribe people from your feed

Allowed API methods (for developers)
POST /vN/users/acceptRequest/:username
POST /vN/users/rejectRequest/:username
POST /vN/users/:username/unsubscribeFromMe
