
/* ============================================================
   Data */

var manager = null;
var repo_commits = new Map();    // owner/repo : String => shas : Arrayof String
var commits_picked = new Map();  // sha : String => boolean

// register_repo_commits : String, String, Arrayof String -> Void
function register_repo_commits(owner, repo, commits) {
    var key = owner + '/' + repo;
    commits = JSON.parse(commits);
    // console.log('register ' + key + ' = ' + commits);
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

function initialize_for_manager(m) {
    manager = m;
    template_repo_section = Handlebars.compile($('#template_repo_section').html());
    template_repo_body = Handlebars.compile($('#template_repo_body').html());

    $.ajax({
        url : '/ajax/manager/' + m,
        dataType : 'json',
        success : function(repos) {
            $.each(repos, function(index, r) {
                add_repo_section(r.owner, r.repo);
            });
        }
    });
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
    $(template_repo_section(info)).appendTo('#repo_section_container');
    $(template_repo_body(info)).appendTo(select_id(info.id).find('.body_container'));
    select_id(info.id).find('.timeago').timeago();
}

function augment_repo_info(info) {
    info.id = 'repo_section_' + info.owner + '_' + info.repo;
    info.ncommits = info.commits.length;
    info.timestamp = (new Date(info.last_polled * 1000)).toISOString();
    $.each(info.commits, function(index, ci) { augment_commit_info(index, ci); });
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
