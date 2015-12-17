/* ============================================================
   Data Types and Storage */

/* Types:

Config = {
  managers: {manager : [owner/repo, ...], ...},
  branch_day: {owner/repo: sha, ...},
}

RepoInfo = {
  owner : String,
  repo : String,
  last_polled : String, -- Date.toISOString()
  master_sha : String / null,
  release_sha : String / null,
  commits : [CommitInfo, ...],  -- unsorted
}

AugmentedRepoInfo = RepoInfo + {
  timestamp : Integer, -- Date.UTC()
  branch_day_sha : String,
  commits_map : Map[sha => CommitInfo],
  master_commits : [AnnotatedCommitInfo, ...],
}

CommitInfo = {
  sha : String,
  author : AuthorInfo, committer : AuthorInfo,
  message : String,
  parents : [ { sha : String, _ }, ... ],
}
AuthorInfo = { name: String, email: String, date: String }

AnnotatedCommitInfo = CommitInfo + {
  status_actual : String ("picked" | "no"),
  status_recommend : String ("attn" | "no")
}

RepoCachedInfo = {
  timestamp: Integer, -- Date.UTC()
  master_sha: String / null,
  release_sha: String / null,
  commits : [CommitInfo, ...] -- unsorted, only commits not in server RepoInfo
}

*/

/* Filesystem:

  data/config.json => Config
  data/repo_{{owner}}_{{repo}} => RepoInfo

*/

/* Local Storage (Cache) -- Data other than plain strings is JSON-encoded

  "repo/{{owner}}/{{repo}}" => RepoCachedInfo

*/

/* ============================================================
   Utilities */

function ok_name(s) {
    return (typeof s === 'string') &&
        /^[_a-zA-Z0-9\-]+$/.test(s);
}

function ok_repo(s) {
    return (typeof s === 'string') &&
        /^([a-zA-Z0-9_\-]+)[\/]([_a-zA-Z0-9\-]+)$/.test(s);
}

function parse_repo(s) {
    var parts = s.split(/[\/]/, 2);
    return {owner: parts[0], repo: parts[1]};
}

function repo_key(owner, repo) {
    return owner + '/' + repo;
}

/* ============================================================
   Ajax */

var cache = {
    config: null,         // Config or null
    repo_info : new Map() // repo_key(owner, repo) => RepoInfo
};

function data_cache_config(k) {
    if (!cache.config) {
        $.ajax({
            url : 'data/config.json',
            dataType : 'json',
            cache : false,
            success : function(data) {
                cache.config = data;
                k(data);
            }
        });
    } else {
        k(cache.config);
    }
}

function data_manager_repos(manager) {
    if (!cache.config) {
        console.log("error: called data_manager_repos before data_cache_config");
        return null;
    } else {
        var repos = cache.config.managers[manager] || [];
        return ($.map(repos, function(repo) { return parse_repo(repo); }));
    }
}

function data_repo_info(owner, repo, k) {
    var key = repo_key(owner, repo);
    if (cache.repo_info.has(key)) {
        k(cache.repo_info.get(key));
    } else {
        $.ajax({
            url : 'data/repo_' + owner + '_' + repo,
            dataType: 'json',
            cache : false,
            success : function(data) {
                merge_local_info(repo_key(owner, repo), data, true);
                augment_repo_info(data);
                cache.repo_info.set(key, data);
                k(data);
            }
        });
    }
}

function merge_local_info(key, info, loud) {
    var localri = localStorage.getItem("repo/" + key);
    localri = localri && JSON.parse(localri);
    if (localri && localri.timestamp > Date.parse(info.last_polled)) {
        if (loud) console.log("local information found: ", key);
        info.timestamp = localri.timestamp;
        info.last_polled = (new Date(localri.timestamp)).toISOString();
        info.master_sha = localri.master_sha;
        info.release_sha = localri.release_sha;
        $.each(localri.commits, function(index, ci) {
            info.commits.push(ci);
        });
    }
}

function gh_poll_repo(owner, repo, k) {
    var ri = cache.repo_info.get(repo_key(owner, repo));
    var now = Date.now();
    augment_repo_info1(ri);
    console.log("github: fetching refs: ", repo_key(owner, repo));
    $.ajax({
        url: 'https://api.github.com/repos/' + owner + '/' + repo + '/git/refs/heads',
        dataType: 'json',
        headers : {
            "If-Modified-Since": (new Date(ri.timestamp)).toUTCString()
        },
        success: function(data, status, jqxhr) {
            if (status == "notmodified") {
                ri.timestamp = now;
                ri.last_polled = (new Date(now)).toISOString();
                k();
            } else {
                gh_update_repo(ri, data, k);
            }
        }});
}

/* FIXME: need to maintain invariant: 
   localStorage commits + server commits = all commits up to localStorage timestamp
   The problem: suppose we check twice, get updates both times.
   Then all commits = Server + Diff1 + Diff2
   But we only store Diff2 commits; Diff1 commits get lost. Whoops.
*/

function gh_update_repo(ri, data, k) {
    // data : [{ref:String, object:{type: ("commit"|?), sha: String}}, ...]
    var timestamp = Date.now();
    var master_sha = ri.master_sha, release_sha = ri.release_sha;
    var heads_to_update = [];
    $.each(data, function(index, refinfo) {
        if (refinfo.ref == 'refs/heads/master') {
            if (refinfo.object.sha != master_sha) {
                master_sha = refinfo.object.sha;
                heads_to_update.push(master_sha);
            }
        } else if (refinfo.ref == 'refs/heads/release') {
            if (refinfo.object.sha != release_sha) {
                release_sha = refinfo.object.sha;
                heads_to_update.push(release_sha);
            }
        }
    });
    gh_get_commits(ri, heads_to_update, function(commits_map) {
        var commits = [];
        commits_map.forEach(function(ci, sha) { commits.push(ci); });
        localStorage.setItem('repo/' + repo_key(ri.owner, ri.repo), JSON.stringify({
            timestamp: timestamp,
            master_sha: master_sha,
            release_sha: release_sha,
            commits: commits
        }));
        merge_local_info(repo_key(ri.owner, ri.repo), ri, false);
        augment_repo_info(ri);
        k();
    });
}

function gh_get_commits(ri, head_shas, k) {
    var new_commits = new Map();
    gh_get_commits_rec(ri, head_shas, new_commits, k, 0);
}

function gh_get_commits_rec(ri, head_shas, new_commits, k, i) {
    if (i < head_shas.length) {
        gh_get_commits1(ri, head_shas[i], new_commits, function() {
            gh_get_commits_rec(ri, head_shas, new_commits, k, i+1);
        });
    } else {
        k(new_commits);
    }
}

function gh_get_commits1(ri, head_sha, new_commits, k) {
    $.ajax({
        url: 'https://api.github.com/repos/' +
            ri.owner + '/' + ri.repo + '/commits?sha=' + head_sha,
        dataType: 'json',
        success: function(data) {
            console.log("github: fetching commits: ", repo_key(ri.owner, ri.repo), head_sha);
            data = $.map(data, function(ci) { return gh_trim_commit_info(ci); });
            var page_map = make_commits_map(data);
            var sha = head_sha;
            while (page_map.has(sha)
                   && !ri.commits_map.has(sha)
                   && sha != ri.branch_day_sha) {
                var ci = page_map.get(sha);
                new_commits.set(sha, ci);
                if (ci.parents.length == 1) {
                    sha = ci.parents[0].sha;
                } else {
                    ri.error_line = "Merge node at commit " + sha;
                    break;
                }
            }
            if (ri.commits_map.has(sha)) {
                k();
            } else if (sha == ri.branch_day_sha) {
                k();
            } else {
                gh_get_commits1(ri, sha, new_commits, k);
            }
        }
    });
}

function gh_trim_commit_info(ci) {
    return {
        sha: ci.sha,
        author: ci.commit.author,
        committer: ci.commit.committer,
        message: ci.commit.message,
        parents: ci.parents
    };
}

function clear_local_storage() {
    localStorage.clear();
}

/* ============================================================ */

function augment_repo_info1(info) {
    info.branch_day_sha = cache.config.branch_day[info.owner + '/' + info.repo];
    info.timestamp = Date.parse(info.last_polled);
    info.commits_map = make_commits_map(info.commits);
    if (!info.error_line) info.error_line = null;  /* may be overridden */
}

function augment_repo_info(info) {
    augment_repo_info1(info);
    info.id = make_repo_id(info.owner, info.repo);
    info.todo_id = make_todo_id(info.owner, info.repo);
    add_release_map(info);
    add_master_chain(info);
    info.commits_ok = (info.error_line == null);
    info.ncommits = info.master_chain.length
}

function make_commits_map(commits) {
    var map = new Map();
    $.each(commits, function(index, commit) {
        map.set(commit.sha, commit);
    });
    return map;
}

function add_release_map(info) {
    var release_map = new Map();
    var sha = info.release_sha;
    var m;
    while (sha && sha != info.branch_day_sha) {
        release_map.set(sha, "shared");
        var ci = info.commits_map.get(sha);
        var rx = /\(cherry picked from commit ([0-9a-z]*)\)/g;
        while (m = rx.exec(ci.message)) {
            var picked_sha = m[1];
            release_map.set(picked_sha, "picked");
        }
        if (ci.parents.length == 1) {
            sha = ci.parents[0].sha;
        } else {
            info.error_line = "Merge node in release branch at commit " + sha;
            sha = null;
        }
    }
    info.release_map = release_map;
}

function add_master_chain(info) {
    /* sets info.{release_map, master_chain, error_line} */
    var chain = [];
    var sha = info.master_sha;
    while (sha && sha != info.branch_day_sha) {
        var ci = info.commits_map.get(sha);
        chain.push(ci);
        if (ci.parents.length == 1) {
            sha = ci.parents[0].sha;
        } else {
            info.error_line = "Merge node in master branch at commit " + sha;
            info.master_chain = [];
            return;
        }
    }
    chain = chain.reverse();
    $.each(chain, function(index, ci) { augment_commit_info(index, ci, info); });
    info.master_chain = chain;
}

function augment_commit_info(index, info, repo_info) {
    info.id = 'commit_' + info.sha;
    info.status_actual = repo_info.release_map.has(info.sha) ? "picked" : "no";
    info.status_recommend = commit_needs_attention(info) ? "attn" : "no";
    info.class_picked =
        (info.status_actual === "picked") ? "commit_picked" : "commit_unpicked";
    info.class_attn = 
        (info.status_recommend === "attn") ? "commit_attn" : "commit_no_attn";
    info.index = index + 1;
    info.short_sha = info.sha.substring(0,8);
    var lines = info.message.split("\n");
    info.class_one_multi = (lines.length > 1) ? "commit_msg_multi" : "commit_msg_one";
    info.message_line1 = lines[0];
    info.message_rest_lines = $.map(lines.slice(1), function (line) {
        return Handlebars.escapeExpression(line) + '<br/>';
    }).join(" ");
    info.is_picked = (info.status_actual === "picked");
    info.nice_date = info.author.date.substring(0, 4 + 1 + 2 + 1 + 2);
}

function commit_needs_attention(ci) {
    return /merge|release/i.test(ci.message);
}

function make_repo_id(owner, repo) {
    return 'repo_section_' + owner + '_' + repo;
}

function make_todo_id(owner, repo) {
    return 'todo_repo_' + owner + '_' + repo;
}
