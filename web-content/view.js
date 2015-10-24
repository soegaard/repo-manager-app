
function select_id(id) {
    return $('#' + id);
}

/* ============================================================
   Repo callbacks */

function toggle_repo_section_body(id) {
    select_id(id).find('.repo_section_body').toggle();
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
