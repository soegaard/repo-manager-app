/* ============================================================
   Data */

var manager = null;
var manager_repos = null;        // [{owner, repo}, ...]
var repo_commits = new Map();    // owner/repo : String => shas : Arrayof String
var commits_picked = new Map();  // sha : String => boolean

function register_repo_commit_list(owner, repo, commits) {
    var key = owner + '/' + repo;
    repo_commits.set(key, commits);
    $.each(commits, function(index, commit) {
        commits_picked.set(commit, false);
    });
    $.ready(function() { todo_repo_update(owner, repo); });
}

function get_repo_commits(owner, repo) {
    var key = owner + '/' + repo;
    return repo_commits.get(key) || [];
}

function set_commit_will_pick(sha, will_pick) {
    commits_picked.set(sha, will_pick);
}

/* ============================================================
   DOM Utilities */

function select_id(id) {
    return $('#' + id);
}

/* ============================================================
   Repo callbacks */

function toggle_body(id) {
    select_id(id).find('.body_container').toggle();
}

function repo_expand_all(id) {
    select_id(id).find('.commit_full_msg').show();
}
function repo_collapse_all(id) {
    select_id(id).find('.commit_full_msg').hide();
}

/* ============================================================
   Commit callbacks */

function toggle_commit_full_message(id) {
    select_id(id).find('.commit_full_msg').toggle();
}

function update_commit_action(id, owner, repo, sha) {
    var new_value = select_id(id).find('.commit_pick_checkbox')[0].checked;
    set_commit_will_pick(sha, new_value);
    todo_repo_update(owner, repo);
}

/* ============================================================
   To Do Summary */

function toggle_todo_body(id) {
    select_id(id).find('.todo_body').toggle();
}

function todo_repo_update(owner, repo) {
    var show_bookkeeping = false;
    $.each(get_repo_commits(owner, repo), function(index, sha) {
        var show_commit = commits_picked.get(sha) || false;
        select_id('todo_commit_' + sha).toggle(show_commit);
        show_bookkeeping = show_bookkeeping || show_commit;
    });

    var todo_id = make_todo_id(owner, repo);
    select_id(todo_id).find('.todo_bookkeeping_line').toggle(show_bookkeeping);
    select_id(todo_id).find('.todo_empty').toggle(!show_bookkeeping);
}

/* ============================================================
   Javascript templating */

var template_repo_section = null;
var template_repo_body = null;
var template_todo_section = null;
var template_todo_body = null;

function initialize_page() {
    var q = parse_url_query();
    var m = q.manager || "";
    initialize_for_manager(m);
}

function parse_url_query() {
    var dict = {};
    var q = (window.location.search || "?").substring(1);
    $.each(q.split(/[?;]/), function (i, assign) {
        assign = assign.split(/[=]/, 2);
        dict[assign[0]] = assign[1] || true;
    });
    return dict;
}

function initialize_for_manager(m) {
    manager = m;
    template_repo_section = Handlebars.compile($('#template_repo_section').html());
    template_repo_body = Handlebars.compile($('#template_repo_body').html());
    template_todo_section = Handlebars.compile($('#template_todo_section').html());
    template_todo_body = Handlebars.compile($('#template_todo_body').html());

    data_manager_repos(m, function(repos) {
        console.log("Repos:", repos);
        // Add stubs sync'ly for ordering, then fill in async'ly
        manager_repos = repos;
        $.each(repos, function(index, r) {
            add_repo_stubs(r.owner, r.repo);
        });
        $.each(repos, function(index, r) {
            add_repo_section(r.owner, r.repo);
        });
    });
}

function add_repo_stubs(owner, repo) {
    var id = make_repo_id(owner, repo);
    var todo_id = make_todo_id(owner, repo);

    $('#repo_section_container').append(
        $('<div/>', { id : id }));
    $('#todo_section_container').append(
        $('<div/>', { id : todo_id }));
}

function add_repo_section(owner, repo) {
    data_repo_info(owner, repo, function(ri) {
        add_repo_section_w_info(ri);
    });
}

function add_repo_section_w_info(info) {
    augment_repo_info(info);

    select_id(info.id).replaceWith( $(template_repo_section(info)) );
    select_id(info.todo_id).replaceWith( $(template_todo_section(info)) );
    update_repo_w_info(info);
}

function update_repo_w_info(info) {
    var s;
    s = select_id(info.id).find('.body_container');
    s.empty().append( $(template_repo_body(info)) );
    s.find('.timeago').timeago();

    s = select_id(info.todo_id).find('.body_container');
    s.empty().append( $(template_todo_body(info)) );
    s.find('.timeago').timeago();

    register_repo_commit_list(
        info.owner, info.repo,
        $.map(info.commits, function(ci) { return ci.sha; }));
}

function checkx_for_updates() {
    var now = (new Date()).toISOString();
    $.each(manager_repos, function(index, r) {
        var s = select_id(make_repo_id(r.owner, r.repo));
        s.find('.repo_status_checking').show();
        data_poll_repo(r.owner, r.repo, function(updated) {
            if (updated) {
                update_repo_info(r.owner, r.repo);
            } else {
                update_repo_timestamp(r.owner, r.repo, now);
            }
        });
    });
}

function update_repo_info(owner, repo) {
    data_repo_info(owner, repo, function(ri) {
        augment_repo_info(ri);
        update_repo_w_info(ri);
        select_id(ri.id).find('.repo_status_checking').hide();
    });
}

function update_repo_timestamp(owner, repo, now) {
    var s = select_id(make_repo_id(owner, repo));
    var st = s.find('.repo_status_line abbr.timeago');
    st.replaceWith($('<abbr class="timeago" title="' + now + '">at ' + now + '</abbr>'));
    s.find('.timeago').timeago();
    s.find('.repo_status_checking').hide();
}
