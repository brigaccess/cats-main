package CATS::UI::Judges;

use strict;
use warnings;

use CATS::DB;
use CATS::IP;
use CATS::Judge;
use CATS::ListView;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template msg res_str url_f references_menu);
use CATS::Web qw(param param_on url_param redirect);

sub edit_frame
{
    init_template('judges_edit.html.tt');

    if (my $jid = url_param('edit')) {
        my ($judge_name, $account_name, $pin_mode) = $dbh->selectrow_array(q~
            SELECT J.nick, A.login, J.pin_mode
            FROM judges J LEFT JOIN accounts A ON A.id = J.account_id WHERE J.id = ?~, undef,
            $jid);
        $t->param(id => $jid, judge_name => $judge_name, account_name => $account_name, pin_mode => $pin_mode);
    }
    $t->param(href_action => url_f('judges'));
}

sub edit_save
{
    my $jid = param('id');
    my $judge_name = param('judge_name') // '';
    my $account_name = param('account_name') // '';
    my $pin_mode = param('pin_mode') // 0;

    $judge_name ne '' && length $judge_name <= 20
        or return msg(1005);

    my $account_id;
    if ($account_name) {
        $account_id = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $account_name) or return msg(1139, $account_name);
    }

    if ($jid) {
        $dbh->do(q~
            UPDATE judges SET nick = ?, account_id = ?, pin_mode = ? WHERE id = ?~, undef,
            $judge_name, $account_id, $pin_mode, $jid);
        $dbh->commit;
        msg(1140, $judge_name);
    }
    else {
        $dbh->do(q~
            INSERT INTO judges (id, nick, account_id, pin_mode, is_alive, alive_date)
            VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)~, undef,
            new_id, $judge_name, $account_id, $pin_mode);
        $dbh->commit;
        msg(1006, $judge_name);
    }
}

sub judges_frame
{
    $is_jury or return;

    if ($is_root) {
        if (my $jid = param('ping')) {
            CATS::Judge::ping($jid);
            return redirect(url_f('judges'));
        }
        defined url_param('new') || defined url_param('edit') and return edit_frame;
    }

    my $lv = CATS::ListView->new(name => 'judges', template => 'judges.html.tt');

    if ($is_root) {
        defined param('edit_save') and edit_save;
        if (my $jid = url_param('delete')) {
            my $judge_name = $dbh->selectrow_array(q~
                SELECT nick FROM judges WHERE id = ?~, undef,
                $jid);
            if ($judge_name) {
                $dbh->do(q~
                    DELETE FROM judges WHERE id = ?~, undef,
                    $jid);
                $dbh->commit;
                msg(1020, $judge_name);
            }
        }
    }

    $lv->define_columns(url_f('judges'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '30%' },
        ($is_root ? ({ caption => res_str(616), order_by => '3', width => '30%' }) : ()),
        { caption => res_str(626), order_by => '4', width => '10%' },
        { caption => res_str(633), order_by => '5', width => '15%' },
        { caption => res_str(622), order_by => '6', width => '10%' },
    ]);
    $lv->define_db_searches([ qw(J.id nick login is_alive alive_date pin_mode account_id last_ip) ]);

    my $c = $dbh->prepare(q~
        SELECT J.id, J.nick, A.login, J.is_alive, J.alive_date, J.pin_mode, A.id, A.last_ip
            FROM judges J LEFT JOIN accounts A ON A.id = J.account_id WHERE 1 = 1 ~ .
            $lv->maybe_where_cond . $lv->order_by);
    $c->execute($lv->where_params);

    my $fetch_record = sub {
        my (
            $jid, $judge_name, $account_name, $is_alive, $alive_date, $pin_mode, $account_id, $last_ip
        ) = $_[0]->fetchrow_array or return ();
        return (
            jid => $jid,
            judge_name => $judge_name,
            account_name => $account_name,
            CATS::IP::linkify_ip($last_ip),
            pin_mode => $pin_mode,
            is_alive => $is_alive,
            alive_date => $alive_date,
            href_ping => url_f('judges', ping => $jid),
            href_edit => url_f('judges', edit => $jid),
            href_delete => url_f('judges', 'delete' => $jid),
            href_account => url_f('users', edit => $account_id),
        );
    };

    $lv->attach(url_f('judges'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('judges') ], editable => $is_root);

    my ($not_processed) = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM reqs WHERE state = ?~, undef,
        $cats::st_not_processed);
    $t->param(not_processed => $not_processed);
}

1;
