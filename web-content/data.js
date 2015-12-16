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
  last_polled : Date (string),
  master_sha : String / null,
  release_sha : String / null,
  commits : [CommitInfo, ...],  -- unsorted
}

AugmentedRepoInfo = RepoInfo + {
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
AuthorInfo = { name = String, email = String, date = String }

AnnotatedCommitInfo = CommitInfo + {
  status_actual : String ("no" | "picked" | "pre-avail"),
  status_recommend : String (...),
}

*/

/* Filesystem:

  /data/config.json => Config
  /data/repo_{{owner}}_{{repo}} => RepoInfo

*/

/* Local Storage

Configuration:

  "github_auth" => OAuth token

Cache:

  -- Data other than plain strings is JSON-encoded.
  "ref_{{owner}}_{{repo}}_{{ref}}" => RefInfo+{ts : TIME}
  "commit_{{sha}}" => CommitInfo

*/

/*
  data_manager_repos(manager, k) => (k repos)
  Manager responsibilities change rarely; just store in files.
  GET /data/manager_{{manager}} => [{owner : owner, repo : repo}, ...]
  
  data_poll_repo(owner, repo, k) uses data_repo_ref_gh(owner, repo, ref, k)

  data_repo_ref_gh(owner, repo, ref, k) hits GitHub, caches locally

  data_repo_ref(owner, repo, ref, k) uses localStorage cache
  localStorage.get("ref:{{owner}}/{{repo}}/{{ref}}") =>
    { sha : String, ts : String }

  data_repo_info(owner, repo, k) 
    uses data_repo_ref to get refs,
    uses data_repo_chain(owner, repo, commit, k) to get chains
 */


/* ============================================================
   Utilities */

function ok_name(s) {
    return (typeof s === 'string') && /^[_a-zA-Z\-]*$/.test(s);
}

function repo_key(owner, repo) {
    return owner + '/' + repo;
}

/* ============================================================
   Ajax */

var cache = {
    config: null,
    repo_info : new Map()
};

function data_get_config(k) {
    if (!cache.config) {
        $.ajax({
            url : '/data/config.json',
            dataType : 'json',
            success : function(data) {
                cache.config = data;
                k(data);
            }
        });
    } else {
        k(cache.config);
    }
}

function data_manager_repos(manager, k) {
    data_get_config(function(config) {
        var repos = config.managers[manager] || [];
        k($.map(repos, function(repo) {
            var parts = repo.split(/[\/]/,2);
            return {owner: parts[0], repo: parts[1]};
        }));
    });
}

function data_repo_info(owner, repo, k) {
    var key = repo_key(owner, repo);
    if (!cache.repo_info[key]) {
        $.ajax({
            url : '/data/repo_' + owner + '_' + repo,
            dataType: 'json',
            success : function(data) {
                cache.repo_info[key] = augment_repo_info(data);
                k(data);
            }
        });
    } else {
        k(cache.repo_info[key]);
    }
}

/* ============================================================ */

function augment_repo_info(info) {
    info.branch_day_sha = cache.config.branch_day[info.owner + '/' + info.repo];
    info.id = make_repo_id(info.owner, info.repo);
    info.todo_id = make_todo_id(info.owner, info.repo);
    info.commits_map = make_commits_map(info.commits);
    info.error_line = null;  /* may be overridden */
    add_release_map(info);
    add_master_chain(info);
    info.commits_ok = (info.error_line == null);
    info.ncommits = info.master_chain.length
    info.timestamp = info.last_polled;
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
    while (sha && sha != info.branch_day_sha) {
        release_map.set(sha, true);
        var ci = info.commits_map.get(sha);
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
    var index = 1;
    while (sha && sha != info.branch_day_sha) {
        var ci = info.commits_map.get(sha);
        augment_commit_info(index, ci, info);
        chain.push(ci);
        if (ci.parents.length == 1) {
            sha = ci.parents[0].sha;
            index++;
        } else {
            info.error_line = "Merge node in master branch at commit " + sha;
            info.master_chain = [];
            return;
        }
    }
    info.master_chain = chain;
}

function augment_commit_info(index, info, repo_info) {
    info.id = 'commit_' + info.sha;
    info.status_actual = repo_info.release_map.get(info.sha) ? "picked" : "no";
    info.status_recommend = (/[Mm]erge|[Rr]elease/.test(info.message)) ? "attn" : "no";
    info.class_picked =
        (info.status_actual === "picked") ? "commit_picked" : "commit_unpicked";
    info.class_attn = 
        (info.status_recommend === "attn") ? "commit_attn" : "commit_no_attn";
    info.index = index;
    info.short_sha = info.sha.substring(0,8);
    info.message_line1 = get_message_line1(info.message);
    info.message_lines = get_message_lines(info.message);
    info.is_picked = (info.status_actual === "picked");
    info.nice_date = info.author.date.substring(0, 4 + 1 + 2 + 1 + 2);
}

function get_message_line1(message) {
    return message.split("\n")[0];
}

function get_message_lines(message) {
    var lines = message.split("\n");
    for (var i = 0; i < lines.length; ++i) {
        lines[i] = Handlebars.escapeExpression(lines[i]) + '<br/>';
    }
    return (lines.join(" "));
}

function make_repo_id(owner, repo) {
    return 'repo_section_' + owner + '_' + repo;
}

function make_todo_id(owner, repo) {
    return 'todo_repo_' + owner + '_' + repo;
}
