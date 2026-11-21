//
//  ModelTests.swift
//  SwiftUISampleAppTests
//

import Foundation
import Testing
@testable import SwiftUISampleApp

/// Decoding and encoding of the search API models.
struct ModelTests {

    @Test func decodesFullSearchResponse() throws {
        let container = try JSONDecoder().decode(RepoContainer.self, from: Self.fullResponseJSON)

        #expect(container.total_count == 1)
        #expect(container.incomplete_results == false)
        let repo = try #require(container.items?.first)

        #expect(repo.id == 44838949)
        #expect(repo.node_id == "MDEwOlJlcG9zaXRvcnk0NDgzODk0OQ==")
        #expect(repo.name == "swift")
        #expect(repo.full_name == "apple/swift")
        #expect(repo.isPrivate == false, "the API's `private` key maps to `isPrivate`")
        #expect(repo.html_url == "https://github.com/apple/swift")
        #expect(repo.description == "The Swift Programming Language")
        #expect(repo.fork == false)
        #expect(repo.created_at == "2015-10-23T21:15:07Z")
        #expect(repo.size == 1000)
        #expect(repo.stargazers_count == 67000)
        #expect(repo.language == "C++")
        #expect(repo.has_issues == true)
        #expect(repo.has_discussions == true)
        #expect(repo.forks_count == 10300)
        #expect(repo.mirror_url == nil)
        #expect(repo.archived == false)
        #expect(repo.open_issues_count == 8000)
        #expect(repo.topics == ["swift", "compiler"])
        #expect(repo.visibility == "public")
        #expect(repo.default_branch == "main")
        #expect(repo.score == 1.0)
        #expect(repo.clone_url == "https://github.com/apple/swift.git")

        let owner = try #require(repo.owner)
        #expect(owner.login == "apple")
        #expect(owner.id == 10639145)
        #expect(owner.avatar_url == "https://avatars.githubusercontent.com/u/10639145?v=4")
        #expect(owner.type == "Organization")
        #expect(owner.site_admin == false)
        #expect(owner.received_events_url == "https://api.github.com/users/apple/received_events")

        let license = try #require(repo.license)
        #expect(license.key == "apache-2.0")
        #expect(license.name == "Apache License 2.0")
        #expect(license.spdx_id == "Apache-2.0")
        #expect(license.url == "https://api.github.com/licenses/apache-2.0")
        #expect(license.node_id == "MDc6TGljZW5zZTI=")
    }

    @Test func missingFieldsDecodeAsNil() throws {
        let container = try JSONDecoder().decode(RepoContainer.self, from: Data("{}".utf8))
        let repo = try JSONDecoder().decode(Repo.self, from: Data("{}".utf8))
        let owner = try JSONDecoder().decode(Owner.self, from: Data("{}".utf8))
        let license = try JSONDecoder().decode(License.self, from: Data("{}".utf8))

        #expect(container.total_count == nil && container.items == nil)
        #expect(repo.id == nil && repo.full_name == nil && repo.owner == nil && repo.license == nil)
        #expect(owner.login == nil && owner.avatar_url == nil)
        #expect(license.key == nil && license.name == nil)
    }

    @Test func wrongTypeFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Repo.self, from: Data(#"{"id":"not a number"}"#.utf8))
        }
    }

    @Test func memberwiseInitRoundTripsThroughJSON() throws {
        let repo = Repo(id: 7, name: "repo", full_name: "owner/repo", isPrivate: true, topics: ["a"], score: 2.5)

        let decoded = try JSONDecoder().decode(Repo.self, from: JSONEncoder().encode(repo))

        #expect(decoded.id == 7)
        #expect(decoded.full_name == "owner/repo")
        #expect(decoded.isPrivate == true)
        #expect(decoded.topics == ["a"])
        #expect(decoded.score == 2.5)
        #expect(decoded.owner == nil)
    }

    @Test func fullResponseRoundTripsThroughJSON() throws {
        let container = try JSONDecoder().decode(RepoContainer.self, from: Self.fullResponseJSON)

        let decoded = try JSONDecoder().decode(RepoContainer.self, from: JSONEncoder().encode(container))

        let repo = try #require(decoded.items?.first)
        #expect(repo.owner?.login == "apple")
        #expect(repo.license?.spdx_id == "Apache-2.0")
        #expect(repo.isPrivate == false)
    }

    @Test func reposAreIdentifiedByID() {
        let a = Repo(id: 1, full_name: "a")
        let sameID = Repo(id: 1, full_name: "renamed")
        let b = Repo(id: 2, full_name: "a")

        #expect(a == sameID)
        #expect(a != b)
        #expect(a.hashValue == sameID.hashValue)
        #expect(Set([a, sameID, b]).count == 2)
        #expect(a.id == 1, "Identifiable uses the API id")
    }

    // MARK: - Fixture

    /// A search response with every field the models know about.
    static let fullResponseJSON = Data("""
    {
      "total_count": 1,
      "incomplete_results": false,
      "items": [{
        "id": 44838949,
        "node_id": "MDEwOlJlcG9zaXRvcnk0NDgzODk0OQ==",
        "name": "swift",
        "full_name": "apple/swift",
        "private": false,
        "owner": {
          "login": "apple",
          "id": 10639145,
          "node_id": "MDEyOk9yZ2FuaXphdGlvbjEwNjM5MTQ1",
          "avatar_url": "https://avatars.githubusercontent.com/u/10639145?v=4",
          "gravatar_id": "",
          "url": "https://api.github.com/users/apple",
          "html_url": "https://github.com/apple",
          "followers_url": "https://api.github.com/users/apple/followers",
          "following_url": "https://api.github.com/users/apple/following{/other_user}",
          "gists_url": "https://api.github.com/users/apple/gists{/gist_id}",
          "starred_url": "https://api.github.com/users/apple/starred{/owner}{/repo}",
          "subscriptions_url": "https://api.github.com/users/apple/subscriptions",
          "organizations_url": "https://api.github.com/users/apple/orgs",
          "repos_url": "https://api.github.com/users/apple/repos",
          "events_url": "https://api.github.com/users/apple/events{/privacy}",
          "received_events_url": "https://api.github.com/users/apple/received_events",
          "type": "Organization",
          "site_admin": false
        },
        "html_url": "https://github.com/apple/swift",
        "description": "The Swift Programming Language",
        "fork": false,
        "url": "https://api.github.com/repos/apple/swift",
        "forks_url": "https://api.github.com/repos/apple/swift/forks",
        "keys_url": "https://api.github.com/repos/apple/swift/keys{/key_id}",
        "collaborators_url": "https://api.github.com/repos/apple/swift/collaborators{/collaborator}",
        "teams_url": "https://api.github.com/repos/apple/swift/teams",
        "hooks_url": "https://api.github.com/repos/apple/swift/hooks",
        "issue_events_url": "https://api.github.com/repos/apple/swift/issues/events{/number}",
        "events_url": "https://api.github.com/repos/apple/swift/events",
        "assignees_url": "https://api.github.com/repos/apple/swift/assignees{/user}",
        "branches_url": "https://api.github.com/repos/apple/swift/branches{/branch}",
        "tags_url": "https://api.github.com/repos/apple/swift/tags",
        "blobs_url": "https://api.github.com/repos/apple/swift/git/blobs{/sha}",
        "git_tags_url": "https://api.github.com/repos/apple/swift/git/tags{/sha}",
        "git_refs_url": "https://api.github.com/repos/apple/swift/git/refs{/sha}",
        "trees_url": "https://api.github.com/repos/apple/swift/git/trees{/sha}",
        "statuses_url": "https://api.github.com/repos/apple/swift/statuses/{sha}",
        "languages_url": "https://api.github.com/repos/apple/swift/languages",
        "stargazers_url": "https://api.github.com/repos/apple/swift/stargazers",
        "contributors_url": "https://api.github.com/repos/apple/swift/contributors",
        "subscribers_url": "https://api.github.com/repos/apple/swift/subscribers",
        "subscription_url": "https://api.github.com/repos/apple/swift/subscription",
        "commits_url": "https://api.github.com/repos/apple/swift/commits{/sha}",
        "git_commits_url": "https://api.github.com/repos/apple/swift/git/commits{/sha}",
        "comments_url": "https://api.github.com/repos/apple/swift/comments{/number}",
        "issue_comment_url": "https://api.github.com/repos/apple/swift/issues/comments{/number}",
        "contents_url": "https://api.github.com/repos/apple/swift/contents/{+path}",
        "compare_url": "https://api.github.com/repos/apple/swift/compare/{base}...{head}",
        "merges_url": "https://api.github.com/repos/apple/swift/merges",
        "archive_url": "https://api.github.com/repos/apple/swift/{archive_format}{/ref}",
        "downloads_url": "https://api.github.com/repos/apple/swift/downloads",
        "issues_url": "https://api.github.com/repos/apple/swift/issues{/number}",
        "pulls_url": "https://api.github.com/repos/apple/swift/pulls{/number}",
        "milestones_url": "https://api.github.com/repos/apple/swift/milestones{/number}",
        "notifications_url": "https://api.github.com/repos/apple/swift/notifications{?since,all,participating}",
        "labels_url": "https://api.github.com/repos/apple/swift/labels{/name}",
        "releases_url": "https://api.github.com/repos/apple/swift/releases{/id}",
        "deployments_url": "https://api.github.com/repos/apple/swift/deployments",
        "created_at": "2015-10-23T21:15:07Z",
        "updated_at": "2026-11-20T08:00:00Z",
        "pushed_at": "2026-11-20T07:59:00Z",
        "git_url": "git://github.com/apple/swift.git",
        "ssh_url": "git@github.com:apple/swift.git",
        "clone_url": "https://github.com/apple/swift.git",
        "svn_url": "https://github.com/apple/swift",
        "homepage": "https://swift.org",
        "size": 1000,
        "stargazers_count": 67000,
        "watchers_count": 67000,
        "language": "C++",
        "has_issues": true,
        "has_projects": false,
        "has_downloads": true,
        "has_wiki": false,
        "has_pages": false,
        "has_discussions": true,
        "forks_count": 10300,
        "mirror_url": null,
        "archived": false,
        "disabled": false,
        "open_issues_count": 8000,
        "license": {
          "key": "apache-2.0",
          "name": "Apache License 2.0",
          "spdx_id": "Apache-2.0",
          "url": "https://api.github.com/licenses/apache-2.0",
          "node_id": "MDc6TGljZW5zZTI="
        },
        "allow_forking": true,
        "is_template": false,
        "web_commit_signoff_required": false,
        "topics": ["swift", "compiler"],
        "visibility": "public",
        "forks": 10300,
        "open_issues": 8000,
        "watchers": 67000,
        "default_branch": "main",
        "score": 1.0
      }]
    }
    """.utf8)
}
