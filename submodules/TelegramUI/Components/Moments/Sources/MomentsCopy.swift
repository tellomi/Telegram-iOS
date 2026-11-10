import Foundation
import TelegramCore
import TelegramPresentationData

public enum MomentsTextKey {
    case title
    case recommend
    case following
    case friends
    case nearby
    case newPosts
    case compose
    case notifications
    case emptyRecommend
    case emptyFollowing
    case emptyFriends
    case emptyNearby
    case publish
    case findPeople
    case switchCity
    case retry
    case loadFailed
    case unavailable
    case edited
    case fullText
    case follow
    case followingState
    case like
    case comment
    case repost
    case quote
    case share
    case save
    case saved
    case more
    case notInterested
    case hidePost
    case mute
    case unmute
    case report
    case copyLink
    case hidden
    case undo
    case audienceEveryone
    case audienceContacts
    case audienceCloseFriends
    case audienceSelected
    case audienceMutual
    case audienceChoose
    case composerTitle
    case cancel
    case draftTitle
    case draftSave
    case draftDiscard
    case draftContinue
    case commentClosed
    case commentPlaceholder
    case sortHot
    case sortLatest
    case nearbyLatest
    case nearbyMixed
    case nearbyPermission
    case settingsTitle
    case settingsFollowing
    case settingsFollowers
    case settingsPublic
    case settingsOnlyMe
    case pushComments
    case pushReplies
    case pushMentions
    case pushFollows
    case pushLikes
    case pushReposts
    case pushNewPosts
    case profilePosts
    case profileReposts
    case profileSaved
    case profileLiked
    case listPrivate
    case search
    case delete
    case edit
    case pin
    case unpin
    case endPoll
    case whoCanSee
    case failedRetry
    case uploading
    case mentionWarning
    case allowNearby
    case friendsHint
    case credentialMissing
    case reply
    case copyText
    case viewReplies
    case pinned
    case sortRelevance
    case repostHeader
    case voice
    case voiceStop
    case voiceFailed
    case commentCount
    case commentPrompt
    case authorTag
    case expandReplies
}

public func momentsText(_ strings: PresentationStrings, _ key: MomentsTextKey) -> String {
    let resolved: String
    let english: String
    let chinese: String
    switch key {
    case .title:
        (resolved, english, chinese) = (strings.Moments_Title, "Moments", "动态")
    case .recommend:
        (resolved, english, chinese) = (strings.Moments_Segment_Recommend, "For You", "推荐")
    case .following:
        (resolved, english, chinese) = (strings.Moments_Segment_Following, "Following", "关注")
    case .friends:
        (resolved, english, chinese) = (strings.Moments_Segment_Friends, "Friends", "好友")
    case .nearby:
        (resolved, english, chinese) = (strings.Moments_Segment_Nearby, "Nearby", "同城")
    case .newPosts:
        (resolved, english, chinese) = (strings.Moments_NewPosts, "New posts", "有新动态")
    case .compose:
        (resolved, english, chinese) = (strings.Moments_Compose, "New post", "发布")
    case .notifications:
        (resolved, english, chinese) = (strings.Moments_Notifications, "Activity", "互动")
    case .emptyRecommend:
        (resolved, english, chinese) = (strings.Moments_Empty_Recommend, "Nothing here yet. Share the first post.", "还没有内容，发布第一条动态吧")
    case .emptyFollowing:
        (resolved, english, chinese) = (strings.Moments_Empty_Following, "People you follow have not posted yet.", "你关注的人还没有发动态")
    case .emptyFriends:
        (resolved, english, chinese) = (strings.Moments_Empty_Friends, "Follow each other and you are friends. Their posts show up here.", "互相关注后就是好友，好友的动态会出现在这里")
    case .emptyNearby:
        (resolved, english, chinese) = (strings.Moments_Empty_Nearby, "No posts in this city yet.", "这座城市还没有动态")
    case .publish:
        (resolved, english, chinese) = (strings.Moments_Publish, "Post", "发布")
    case .findPeople:
        (resolved, english, chinese) = (strings.Moments_FindPeople, "Find people", "找人关注")
    case .switchCity:
        (resolved, english, chinese) = (strings.Moments_SwitchCity, "Change city", "切换城市")
    case .retry:
        (resolved, english, chinese) = (strings.Moments_Retry, "Couldn't load. Tap to retry.", "加载失败，点击重试")
    case .loadFailed:
        (resolved, english, chinese) = (strings.Moments_LoadFailed, "Could not load. Tap to retry.", "加载失败，点击重试")
    case .unavailable:
        (resolved, english, chinese) = (strings.Moments_Unavailable, "Content unavailable", "内容不可用")
    case .edited:
        (resolved, english, chinese) = (strings.Moments_Edited, "Edited", "已编辑")
    case .fullText:
        (resolved, english, chinese) = (strings.Moments_FullText, "Full text", "全文")
    case .follow:
        (resolved, english, chinese) = (strings.Moments_Follow, "Follow", "关注")
    case .followingState:
        (resolved, english, chinese) = (strings.Moments_FollowingState, "Following", "已关注")
    case .like:
        (resolved, english, chinese) = (strings.Moments_Like, "Like", "点赞")
    case .comment:
        (resolved, english, chinese) = (strings.Moments_Comment, "Comment", "评论")
    case .repost:
        (resolved, english, chinese) = (strings.Moments_Repost, "Repost", "转发")
    case .quote:
        (resolved, english, chinese) = (strings.Moments_Quote, "Quote", "引用")
    case .share:
        (resolved, english, chinese) = (strings.Moments_Share, "Share", "分享")
    case .save:
        (resolved, english, chinese) = (strings.Moments_Save, "Save", "收藏")
    case .saved:
        (resolved, english, chinese) = (strings.Moments_Saved, "Saved", "已收藏")
    case .more:
        (resolved, english, chinese) = (strings.Moments_More, "More", "更多")
    case .notInterested:
        (resolved, english, chinese) = (strings.Moments_NotInterested, "Not interested", "不感兴趣")
    case .hidePost:
        (resolved, english, chinese) = (strings.Moments_HidePost, "Hide this post", "隐藏该帖子")
    case .mute:
        (resolved, english, chinese) = (strings.Moments_Mute, "Mute in feed", "屏蔽动态")
    case .unmute:
        (resolved, english, chinese) = (strings.Moments_Unmute, "Unmute in feed", "取消屏蔽")
    case .report:
        (resolved, english, chinese) = (strings.Moments_Report, "Report", "举报")
    case .copyLink:
        (resolved, english, chinese) = (strings.Moments_CopyLink, "Copy link", "复制链接")
    case .hidden:
        (resolved, english, chinese) = (strings.Moments_Hidden, "Hidden", "已隐藏")
    case .undo:
        (resolved, english, chinese) = (strings.Moments_Undo, "Undo", "撤销")
    case .audienceEveryone:
        (resolved, english, chinese) = (strings.Moments_Audience_Everyone, "Everyone", "所有人")
    case .audienceContacts:
        (resolved, english, chinese) = (strings.Moments_Audience_Contacts, "Contacts", "联系人")
    case .audienceCloseFriends:
        (resolved, english, chinese) = (strings.Moments_Audience_CloseFriends, "Close Friends", "密友")
    case .audienceSelected:
        (resolved, english, chinese) = (strings.Moments_Audience_Selected, "Selected people", "选定的人")
    case .audienceMutual:
        (resolved, english, chinese) = (strings.Moments_Audience_Mutual, "Mutual followers", "互关好友")
    case .audienceChoose:
        (resolved, english, chinese) = (strings.Moments_Audience_Choose, "Who can see this: choose", "谁可以看：请选择")
    case .composerTitle:
        (resolved, english, chinese) = (strings.Moments_Composer_Title, "New post", "新动态")
    case .cancel:
        (resolved, english, chinese) = (strings.Common_Cancel, "Cancel", "取消")
    case .draftTitle:
        (resolved, english, chinese) = (strings.Moments_Draft_Title, "Save this draft?", "保存这份草稿？")
    case .draftSave:
        (resolved, english, chinese) = (strings.Moments_Draft_Save, "Save draft", "保存草稿")
    case .draftDiscard:
        (resolved, english, chinese) = (strings.Moments_Draft_Discard, "Discard", "放弃")
    case .draftContinue:
        (resolved, english, chinese) = (strings.Moments_Draft_Continue, "Keep editing", "继续编辑")
    case .commentClosed:
        (resolved, english, chinese) = (strings.Moments_Comment_Closed, "Comments are turned off", "作者已关闭评论")
    case .commentPlaceholder:
        (resolved, english, chinese) = (strings.Moments_Comment_Placeholder, "Reply", "回复")
    case .sortHot:
        (resolved, english, chinese) = (strings.Moments_Sort_Hot, "Top", "热门")
    case .sortLatest:
        (resolved, english, chinese) = (strings.Moments_Sort_Latest, "Latest", "最新")
    case .nearbyLatest:
        (resolved, english, chinese) = (strings.Moments_Nearby_Latest, "Latest", "最新")
    case .nearbyMixed:
        (resolved, english, chinese) = (strings.Moments_Nearby_Mixed, "For you", "综合")
    case .nearbyPermission:
        (resolved, english, chinese) = (strings.Moments_Nearby_Permission, "Location is only used to pick your city. It is not saved.", "只用来确定你所在的城市，不保存位置")
    case .settingsTitle:
        (resolved, english, chinese) = (strings.Moments_Settings_Title, "Moments", "动态")
    case .settingsFollowing:
        (resolved, english, chinese) = (strings.Moments_Settings_FollowingList, "Who can see my following", "谁能看到我的关注列表")
    case .settingsFollowers:
        (resolved, english, chinese) = (strings.Moments_Settings_FollowersList, "Who can see my followers", "谁能看到我的粉丝列表")
    case .settingsPublic:
        (resolved, english, chinese) = (strings.Moments_Settings_Public, "Everyone", "公开")
    case .settingsOnlyMe:
        (resolved, english, chinese) = (strings.Moments_Settings_OnlyMe, "Only me", "仅自己")
    case .pushComments:
        (resolved, english, chinese) = (strings.Moments_Push_Comments, "Comments", "评论")
    case .pushReplies:
        (resolved, english, chinese) = (strings.Moments_Push_Replies, "Replies", "回复")
    case .pushMentions:
        (resolved, english, chinese) = (strings.Moments_Push_Mentions, "Mentions", "提及")
    case .pushFollows:
        (resolved, english, chinese) = (strings.Moments_Push_Follows, "New followers", "新关注")
    case .pushLikes:
        (resolved, english, chinese) = (strings.Moments_Push_Likes, "Likes", "点赞")
    case .pushReposts:
        (resolved, english, chinese) = (strings.Moments_Push_Reposts, "Reposts and quotes", "转发和引用")
    case .pushNewPosts:
        (resolved, english, chinese) = (strings.Moments_Push_NewPosts, "Posts from people you follow", "关注对象的新帖")
    case .profilePosts:
        (resolved, english, chinese) = (strings.Moments_Profile_Posts, "Posts", "帖子")
    case .profileReposts:
        (resolved, english, chinese) = (strings.Moments_Profile_Reposts, "Reposts", "转发")
    case .profileSaved:
        (resolved, english, chinese) = (strings.Moments_Profile_Saved, "Saved posts", "动态收藏")
    case .profileLiked:
        (resolved, english, chinese) = (strings.Moments_Profile_Liked, "Liked", "赞过")
    case .listPrivate:
        (resolved, english, chinese) = (strings.Moments_ListPrivate, "This list is private", "对方未公开")
    case .search:
        (resolved, english, chinese) = (strings.Moments_Search, "Moments", "动态")
    case .delete:
        (resolved, english, chinese) = (strings.Common_Delete, "Delete", "删除")
    case .edit:
        (resolved, english, chinese) = (strings.Moments_Edit, "Edit", "编辑")
    case .pin:
        (resolved, english, chinese) = (strings.Moments_Pin, "Pin to profile", "置顶到资料页")
    case .unpin:
        (resolved, english, chinese) = (strings.Moments_Unpin, "Unpin", "取消置顶")
    case .endPoll:
        (resolved, english, chinese) = (strings.Moments_EndPoll, "End poll", "结束投票")
    case .whoCanSee:
        (resolved, english, chinese) = (strings.Moments_WhoCanSee, "Who can see this", "谁可以看")
    case .failedRetry:
        (resolved, english, chinese) = (strings.Moments_FailedRetry, "Could not post. Retry", "发布失败 · 重试")
    case .uploading:
        (resolved, english, chinese) = (strings.Moments_Uploading, "Posting", "发布中")
    case .mentionWarning:
        (resolved, english, chinese) = (strings.Moments_MentionWarning, "These people cannot see this post and will not be notified.", "以下用户看不到这条动态，也不会收到提醒")
    case .allowNearby:
        (resolved, english, chinese) = (strings.Moments_AllowNearby, "Show in Nearby", "在同城展示")
    case .friendsHint:
        (resolved, english, chinese) = (strings.Moments_FriendsHint, "Friends are people you follow who follow you back.", "互相关注后就是好友")
    case .credentialMissing:
        (resolved, english, chinese) = (strings.Moments_CredentialMissing, "Moments is not connected yet.", "动态服务还没有连接")
    case .reply:
        (resolved, english, chinese) = (strings.Moments_Reply, "Reply", "回复")
    case .copyText:
        (resolved, english, chinese) = (strings.Moments_CopyText, "Copy text", "复制文字")
    case .viewReplies:
        (resolved, english, chinese) = (strings.Moments_ViewReplies, "View replies", "查看回复")
    case .pinned:
        (resolved, english, chinese) = (strings.Moments_Pinned, "Pinned", "置顶")
    case .sortRelevance:
        (resolved, english, chinese) = (strings.Moments_Sort_Relevance, "Relevance", "相关度")
    case .repostHeader:
        (resolved, english, chinese) = (strings.Moments_RepostHeader, "reposted", "转发了")
    case .voice:
        (resolved, english, chinese) = (strings.Moments_Voice, "Voice", "语音")
    case .voiceStop:
        (resolved, english, chinese) = (strings.Moments_VoiceStop, "Stop", "停止")
    case .voiceFailed:
        (resolved, english, chinese) = (strings.Moments_VoiceFailed, "Could not record a voice post.", "语音没有录上")
    case .commentCount:
        (resolved, english, chinese) = (strings.Moments_CommentCount, "comments", "条评论")
    case .commentPrompt:
        (resolved, english, chinese) = (strings.Moments_CommentPrompt, "Say something", "发条评论，说说你的感受")
    case .authorTag:
        (resolved, english, chinese) = (strings.Moments_AuthorTag, "Author", "作者")
    case .expandReplies:
        (resolved, english, chinese) = (strings.Moments_ExpandReplies, "replies", "条回复")
    }
    let codes = [strings.primaryComponent.languageCode, strings.baseLanguageCode].map { $0.lowercased() }
    if codes.contains(where: { $0.hasPrefix("zh") }), resolved == english || resolved.isEmpty {
        return chinese
    }
    return resolved
}

public func momentsReportReasonCode(_ reason: ReportReason) -> String {
    switch reason {
    case .spam:
        return "spam"
    case .fake:
        return "fake"
    case .violence:
        return "violence"
    case .porno:
        return "pornography"
    case .childAbuse:
        return "child_abuse"
    case .copyright:
        return "copyright"
    case .illegalDrugs:
        return "illegal_drugs"
    case .personalDetails:
        return "personal_details"
    case .irrelevantLocation:
        return "irrelevant_location"
    case .custom:
        return "other"
    }
}
