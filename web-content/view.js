/* ============================================================
   Data */

var view_state = {
    repos : [],                 // [{owner: String, repo: String}, ...]
    repo_commits : new Map(),   // owner/repo: String => [sha: String, ...]
    commits_picked : new Map()  // sha: String => boolean
};

function register_repo_commit_list(owner, repo, commits) {
    var key = repo_key(owner, repo);
    view_state.repo_commits.set(key, commits);
    $.each(commits, function(index, commit) {
        view_state.commits_picked.set(commit, false);
    });
    $.ready(function() { todo_repo_update(owner, repo); });
}

function get_repo_commits(owner, repo) {
    return view_state.repo_commits.get(repo_key(owner, repo)) || [];
}

function set_commit_will_pick(sha, will_pick) {
    view_state.commits_picked.set(sha, will_pick);
}

/* ============================================================
   DOM Utilities */

function select_id(id) {
    return $('#' + id);
}

/* ============================================================
   Repo callbacks */

function repo_expand_all(id) {
    select_id(id).find('.commit_rest_msg').show();
}
function repo_collapse_all(id) {
    select_id(id).find('.commit_rest_msg').hide();
}

/* ============================================================
   Commit callbacks */

function toggle_commit_full_message(id) {
    select_id(id).find('.commit_rest_msg').toggle();
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
    var show_repo = false;
    $.each(get_repo_commits(owner, repo), function(index, sha) {
        var show_commit = view_state.commits_picked.get(sha) || false;
        select_id('todo_commit_' + sha).toggle(show_commit);
        show_repo = show_repo || show_commit;
    });

    var todo_id = make_todo_id(owner, repo);
    select_id(todo_id).toggle(show_repo);
}

/* ============================================================
   Javascript templating */

var template_repo_section = null;
var template_repo_body = null;
var template_todo_section = null;
var template_todo_body = null;

function initialize_page() {
    template_repo_section = Handlebars.compile($('#template_repo_section').html());
    template_repo_body = Handlebars.compile($('#template_repo_body').html());
    template_todo_section = Handlebars.compile($('#template_todo_section').html());
    template_todo_body = Handlebars.compile($('#template_todo_body').html());
    var q = parse_url_query();

    if (ok_repo(q.repo)) {
        $("#main_header").html("Repository: " + q.repo);
    } else if (ok_name(q.manager)) {
        $("#main_header").html("Repositories managed by: " + q.manager);
    } else {
        $(".uninitialized_text").toggle(true);
    }

    data_cache_config(function() {
        var select = select_id('navigation');
        $.each(Object.keys(cache.config.managers).sort(), function(index, entry) {
            select.append($('<option />', { 
                html: "manager: " + entry,
                value: "manager=" + entry }));
        });
        $.each(Object.keys(cache.config.branch_day).sort(), function(index, entry) {
            select.append($('<option />', {
                html: "repo: " + entry,
                value: "repo=" + entry }));
        });
        select.change(function() {
            var s = select[0];
            var q = s.options[s.selectedIndex].value;
            window.location.search = '?' + q;
        });

        if (ok_repo(q.repo)) {
            initialize_for_repo(q.repo);
        } else if (ok_name(q.manager)) {
            initialize_for_manager(q.manager);
        }
    });
}

function parse_url_query() {
    var dict = {};
    var q = (window.location.search || "?").substring(1);
    $.each(q.split(/[&;]/), function (i, assign) {
        assign = assign.split(/[=]/, 2);
        dict[assign[0]] = assign[1] || true;
    });
    return dict;
}

function initialize_for_manager(m) {
    initialize_w_repos(data_manager_repos(m));
}

function initialize_for_repo(repo) {
    initialize_w_repos([parse_repo(repo)]);
}

function initialize_w_repos(repos) {
    // Add stubs sync'ly for ordering, then fill in async'ly
    view_state.repos = repos;
    $.each(repos, function(index, r) {
        add_repo_stubs(r.owner, r.repo);
    });
    $.each(repos, function(index, r) {
        add_repo_section(r.owner, r.repo);
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

function check_all_for_updates() {
    $.each(view_state.repos, function(index, r) {
        check_repo_for_updates(r.owner, r.repo);
    });
}

function check_repo_for_updates(owner, repo) {
    var now = (new Date()).toISOString();
    var s = select_id(make_repo_id(owner, repo));
    s.find('.repo_status_checking').show();
    gh_poll_repo(owner, repo, function() {
        update_repo_info(owner, repo);
    });
}

function update_repo_info(owner, repo) {
    data_repo_info(owner, repo, function(ri) {
        update_repo_w_info(ri);
        select_id(ri.id).find('.repo_status_checking').hide();
    });
}
