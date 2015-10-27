
/* ============================================================
   Data */

var manager = null;
var repo_commits = new Map();    // owner/repo : String => shas : Arrayof String
var commits_picked = new Map();  // sha : String => boolean

// register_repo_commits : String, String, Arrayof String -> Void
function register_repo_commits(owner, repo, commits) {
    register_repo_commit_list(owner, repo, JSON.parse(commits));
}

function register_repo_commit_list(owner, repo, commits) {
    var key = owner + '/' + repo;
    // console.log("setting repo_commits for " + key + " to " + commits);
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
    // console.log('setting check = ' + will_pick + ' for ' + sha);
    commits_picked.set(sha, will_pick);
}

function check_for_updates() {
    $.ajax({
        url : '/ajax/poll/' + manager,
        dataType : 'json',
        success : function(data) {
            var now = (new Date()).toISOString();
            var s = $('.repo_status_line abbr.timeago');
            s.replaceWith('<abbr class="timeago" title="' + now + '">at ' + now + '</abbr>');
            s = $('abbr.timeago');
            s.timeago();
            $.each(data, function(index, entry) {
                update_body_container('repo_section_' + entry.owner + '_' + entry.repo,
                                      '/ajax/repo-html/' + entry.owner + '/' + entry.repo);
                update_body_container('todo_repo_' + entry.owner + '_' + entry.repo,
                                      '/ajax/todo-html/' + entry.owner + '/' + entry.repo);
            });
        }
    });
}

function update_body_container(id, url) {
    var s = select_id(id).find('.body_container');
    $.ajax({
        url : url,
        dataType : 'html',
        success : function(contents) {
            s.html(contents);
            $('abbr.timeago').timeago();
        }
    });
}

/* Mysteriously, the document ready handler was getting called after
 * one repo_section even when there were multiple sections on the
 * page. */
function final_setup() {
    // Clear all of the checkboxes
    $(document).ready(function($) {
        $('.commit_pick_checkbox').each(function(index, elem) { 
            elem.checked = false; 
        });
        $('abbr.timeago').timeago();
        // console.log('timeago selector length = ' + $('.timeago').length);
        // console.log('body container length = ' + $('.body_container').length);
    });
}

/* ============================================================
   General helpers */

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
    // console.log("in todo_repo_update, owner = " + owner + ", repo = " + repo);
    // console.log("commits = " + get_repo_commits(owner, repo));
    $.each(get_repo_commits(owner, repo), function(index, sha) {
        var show_commit = commits_picked.get(sha) || false;
        // console.log('commit ' + sha + ' => ' + show_commit);
        select_id('todo_commit_' + sha).toggle(show_commit);
        show_bookkeeping = show_bookkeeping || show_commit;
    });

    select_id('todo_repo_' + owner + '_' + repo).find('.todo_bookkeeping_line').toggle(show_bookkeeping);
    select_id('todo_repo_' + owner + '_' + repo).find('.todo_empty').toggle(!show_bookkeeping);
}


/* ============================================================
   Javascript templating */

var template_repo_section = null;
var template_repo_body = null;
var template_todo_section = null;
var template_todo_body = null;

function initialize_for_manager(m) {
    manager = m;
    template_repo_section = Handlebars.compile($('#template_repo_section').html());
    template_repo_body = Handlebars.compile($('#template_repo_body').html());
    template_todo_section = Handlebars.compile($('#template_todo_section').html());
    template_todo_body = Handlebars.compile($('#template_todo_body').html());

    $.ajax({
        url : '/ajax/manager/' + m,
        dataType : 'json',
        success : function(repos) {
            // Add stubs sync'ly for ordering, then fill in async'ly
            $.each(repos, function(index, r) {
                add_repo_stubs(r.owner, r.repo);
            });
            $.each(repos, function(index, r) {
                add_repo_section(r.owner, r.repo);
            });
        }
    });
}

function add_repo_stubs(owner, repo) {
    var id = 'repo_section_' + owner + '_' + repo;
    var todo_id = 'todo_repo_' + owner + '_' + repo;

    $('#repo_section_container').append(
        $('<div/>', { id : id }));
    $('#todo_section_container').append(
        $('<div/>', { id : todo_id }));
}

function add_repo_section(owner, repo) {
    $.ajax({
        url : '/ajax/repo/' + owner + '/' + repo,
        dataType: 'json',
        success : function(ri) {
            add_repo_section_w_info(ri);
        }
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

function augment_repo_info(info) {
    info.id = 'repo_section_' + info.owner + '_' + info.repo;
    info.todo_id = 'todo_repo_' + info.owner + '_' + info.repo;
    info.commits_ok = Array.isArray(info.commits);
    info.ncommits = info.commits_ok ? info.commits.length : 0;
    info.error_line = info.commits_ok ? "" : info.commits;
    info.timestamp = (new Date(info.last_polled * 1000)).toISOString();
    if (info.commits_ok) {
        $.each(info.commits, function(index, ci) { augment_commit_info(index, ci); });
    } else {
        info.commits = [];
    }
}

function augment_commit_info(index, info) {
    info.id = 'commit_' + info.info.sha;
    info.class_picked =
        (info.status_actual === "picked") ? "commit_picked" : "commit_unpicked";
    info.class_attn = 
        (info.status_recommend === "attn") ? "commit_attn" : "commit_no_attn";
    info.index = index + 1;
    info.sha = info.info.sha;
    info.short_sha = info.sha.substring(0,8);
    info.message_line1 = get_message_line1(info.info.message);
    info.message_lines = get_message_lines(info.info.message);
    info.is_picked = (info.status_actual === "picked");
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

function checkx_for_updates() {
    $.ajax({
        url : '/ajax/poll/' + manager,
        dataType : 'json',
        success : function(data) {
            var now = (new Date()).toISOString();
            var s = $('.repo_status_line abbr.timeago');
            s.replaceWith('<abbr class="timeago" title="' + now + '">at ' + now + '</abbr>');
            $('abbr.timeago').timeago();
            $.each(data, function(index, entry) {
                console.log("update " + entry.owner + '/' + entry.repo);
                update_repo_section(entry.owner, entry.repo);
            });
        }
    });
}

function update_repo_info(owner, repo) {
    $.ajax({
        url : '/ajax/repo/' + owner + '/' + repo,
        dataType : 'json',
        success : function(ri) {
            update_repo_w_info(ri);
        }
    });
}
