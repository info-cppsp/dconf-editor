/*
  This file is part of Dconf Editor

  Dconf Editor is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Dconf Editor is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

using Gtk;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-search.ui")]
class RegistrySearch : Grid, PathElement, BrowsableView
{
    public Behaviour behaviour { private get; set; }

    [GtkChild] private ScrolledWindow scrolled;

    [GtkChild] private ListBox key_list_box;

    private GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    private bool _small_keys_list_rows;
    public bool small_keys_list_rows
    {
        set
        {
            _small_keys_list_rows = value;
            key_list_box.foreach((row) => {
                    Widget row_child = ((ListBoxRow) row).get_child ();
                    if (row_child is KeyListBoxRow)
                        ((KeyListBoxRow) row_child).small_keys_list_rows = value;
                });
        }
    }

    public ModificationsRevealer revealer { private get; set; }

    private BrowserView? _browser_view = null;
    private BrowserView browser_view {
        get {
            if (_browser_view == null)
                _browser_view = (BrowserView) DConfWindow._get_parent (DConfWindow._get_parent (this));
            return (!) _browser_view;
        }
    }

    private DConfWindow? _window = null;
    private DConfWindow window {
        get {
            if (_window == null)
                _window = (DConfWindow) DConfWindow._get_parent (DConfWindow._get_parent (DConfWindow._get_parent (browser_view)));
            return (!) _window;
        }
    }

    private GLib.ListStore search_results_model = new GLib.ListStore (typeof (SettingObject));

    construct
    {
        key_list_box.set_header_func (update_search_results_header);
    }

    /*\
    * * Updating
    \*/
/*
    public void select_row_named (string selected, bool grab_focus)
    {
        check_resize ();
        ListBoxRow? row = key_list_box.get_row_at_index (get_row_position (selected));
        if (row == null)
            assert_not_reached ();
        scroll_to_row ((!) row, grab_focus);
    }
    public void select_first_row (bool grab_focus)
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            scroll_to_row ((!) row, grab_focus);
    }
    private int get_row_position (string selected)
        requires (key_model != null)
    {
        uint position = 0;
        while (position < ((!) key_model).get_n_items ())
        {
            SettingObject object = (SettingObject) ((!) key_model).get_object (position);
            if (object.full_name == selected)
                return (int) position;
            position++;
        }
        assert_not_reached ();
    } */
    private void scroll_to_row (ListBoxRow row, bool grab_focus)
    {
        key_list_box.select_row (row);
        if (grab_focus)
            row.grab_focus ();

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);
        key_list_box.get_adjustment ().set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
    }

    private void ensure_selection ()
    {
        ListBoxRow? row = key_list_box.get_selected_row ();
        if (row == null)
            select_first_row ();
    }

    private void select_first_row ()
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            key_list_box.select_row ((!) row);
        key_list_box.get_adjustment ().set_value (0);
    }

    /*\
    * * Key ListBox
    \*/

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;
        string full_name = setting_object.full_name;
        string parent_path;
        if (full_name.has_suffix ("/"))
            parent_path = SettingsModel.get_base_path (full_name [0:full_name.length - 1]);
        else
            parent_path = SettingsModel.get_base_path (full_name);
        bool is_local_result = parent_path == window.current_path;
        ulong on_delete_call_handler;

        if (setting_object is Directory)
        {
            row = new FolderListBoxRow (setting_object.name, setting_object.full_name, !is_local_result);
            on_delete_call_handler = row.on_delete_call.connect (() => browser_view.reset_objects (((Directory) setting_object).key_model, true));
        }
        else
        {
            if (setting_object is GSettingsKey)
                row = new KeyListBoxRowEditable ((GSettingsKey) setting_object, !is_local_result);
            else
                row = new KeyListBoxRowEditableNoSchema ((DConfKey) setting_object, !is_local_result);

            Key key = (Key) setting_object;
            KeyListBoxRow key_row = (KeyListBoxRow) row;
            key_row.small_keys_list_rows = _small_keys_list_rows;

            on_delete_call_handler = row.on_delete_call.connect (() => set_key_value (key, null));
            ulong set_key_value_handler = key_row.set_key_value.connect ((variant) => { set_key_value (key, variant); set_delayed_icon (row, key); });
            ulong change_dismissed_handler = key_row.change_dismissed.connect (() => revealer.dismiss_change (key));

            ulong key_planned_change_handler = key.notify ["planned-change"].connect (() => set_delayed_icon (row, key));
            ulong key_planned_value_handler = key.notify ["planned-value"].connect (() => set_delayed_icon (row, key));
            set_delayed_icon (row, key);

            row.destroy.connect (() => {
                    key_row.disconnect (set_key_value_handler);
                    key_row.disconnect (change_dismissed_handler);
                    key.disconnect (key_planned_change_handler);
                    key.disconnect (key_planned_value_handler);
                });
        }

        ulong on_row_clicked_handler = row.on_row_clicked.connect (() => request_path (setting_object.full_name));
        ulong on_row_open_parent_handler = row.on_open_parent.connect (() => {
                request_path (parent_path); // TODO selected
            });
        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);

        row.destroy.connect (() => {
                row.disconnect (on_delete_call_handler);
                row.disconnect (on_row_clicked_handler);
                row.disconnect (on_row_open_parent_handler);
                row.disconnect (button_press_event_handler);
            });

        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();
        wrapper.set_halign (Align.CENTER);
        wrapper.add (row);
        if (row is FolderListBoxRow)
            wrapper.get_style_context ().add_class ("folder-row");
        else
            wrapper.get_style_context ().add_class ("key-row");
        return wrapper;
    }

    private void set_delayed_icon (ClickableListBoxRow row, Key key)
    {
        if (key.planned_change)
        {
            StyleContext context = row.get_style_context ();
            context.add_class ("delayed");
            if (key is DConfKey)
            {
                if (key.planned_value == null)
                    context.add_class ("erase");
                else
                    context.remove_class ("erase");
            }
        }
        else
            row.get_style_context ().remove_class ("delayed");
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            ClickableListBoxRow row = (ClickableListBoxRow) widget;

            int event_x = (int) event.x;
            if (event.window != widget.get_window ())   // boolean value switch
            {
                int widget_x, unused;
                event.window.get_position (out widget_x, out unused);
                event_x += widget_x;
            }

            row.show_right_click_popover (get_current_delay_mode (), event_x);
            rows_possibly_with_popover.append (row);
        }

        return false;
    }

    public bool return_pressed ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).on_row_clicked ();

        return true;
    }

    public bool up_or_down_pressed (bool grab_focus, bool is_down)
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        uint n_items = search_results_model.get_n_items ();

        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            ListBoxRow? row = null;
            if (!is_down && (position >= 1))
                row = key_list_box.get_row_at_index (position - 1);
            if (is_down && (position < n_items - 1))
                row = key_list_box.get_row_at_index (position + 1);

            if (row != null)
                scroll_to_row ((!) row, grab_focus);

            return true;
        }
        else if (n_items >= 1)
        {
            key_list_box.select_row (key_list_box.get_row_at_index (is_down ? 0 : (int) n_items - 1));
            return true;
        }
        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        ((ClickableListBoxRow) list_box_row.get_child ()).on_row_clicked ();
    }

    public void invalidate_popovers ()
    {
        uint position = 0;
        ClickableListBoxRow? row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (0);
        while (row != null)
        {
            ((!) row).destroy_popover ();
            position++;
            row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (position);
        }
        rows_possibly_with_popover.remove_all ();
    }

    /*public string? get_selected_row_name ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            return ((SettingObject) ((!) key_model).get_object (position)).full_name;
        }
        else
            return null;
    }*/

    /*\
    * * Revealer stuff
    \*/

    public bool get_current_delay_mode ()
    {
        return browser_view.get_current_delay_mode ();
    }

    private void set_key_value (Key key, Variant? new_value)
    {
        if (get_current_delay_mode ())
            revealer.add_delayed_setting (key, new_value);
        else if (new_value != null)
            key.value = (!) new_value;
        else if (key is GSettingsKey)
            ((GSettingsKey) key).set_to_default ();
        else if (behaviour != Behaviour.UNSAFE)
        {
            browser_view.enter_delay_mode ();
            revealer.add_delayed_setting (key, null);
        }
        else
            ((DConfKey) key).erase ();
    }

    /*\
    * * Keyboard calls
    \*/

    public bool show_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();
        row.show_right_click_popover (get_current_delay_mode ());
        rows_possibly_with_popover.append (row);
        return true;
    }

    public string? get_copy_text ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;
        else
            return ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ();
    }

    public void toggle_boolean_key ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            return;

        ((KeyListBoxRow) ((!) selected_row).get_child ()).toggle_boolean_key ();
    }

    public void set_to_default ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).on_delete_call ();
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).hide_right_click_popover ();
    }

    /*\
    * * Search
    \*/

    private string? old_term;
    // indices for the start of each section. used to know where to insert search hits and to update the headers
    // must be updated before changing the list model, so that the header function works correctly
    private int post_local;
    private int post_bookmarks;
    private int post_folders;
    private uint? search_source = null;
    private GLib.Queue<Directory> search_nodes = new GLib.Queue<Directory> ();

    public void stop_search ()
    {
        key_list_box.bind_model (null, null);
        stop_global_search ();
        search_results_model.remove_all ();
        post_local = -1;
        post_bookmarks = -1;
        post_folders = -1;
        old_term = null;
    }

    public void start_search (string term)
    {
        if (old_term != null && term == (!) old_term)
        {
            ensure_selection ();
            return;
        }

        SettingsModel model = window.model;
        string current_path = window.current_path;
        if (old_term != null && term.has_prefix ((!) old_term))
        {
            pause_global_search ();
            refine_local_results (term);
            refine_bookmarks_results (term);
            if ((!) old_term == "")
                start_global_search (model, current_path, term);
            else
            {
                refine_global_results (term);
                resume_global_search (current_path, term); // update search term
            }

            ensure_selection ();
        }
        else
        {
            stop_global_search ();
            search_results_model.remove_all ();
            post_local = -1;
            post_folders = -1;

            local_search (model, SettingsModel.get_base_path (current_path), term);
            bookmark_search (model, current_path, term);
            key_list_box.bind_model (search_results_model, new_list_box_row);

            select_first_row ();

            if (term != "")
                start_global_search (model, current_path, term);
        }
        old_term = term;
    }

    private void refine_local_results (string term)
    {
        for (int i = post_local - 1; i >= 0; i--)
        {
            SettingObject item = (SettingObject) search_results_model.get_item (i);
            if (!(term in item.name))
            {
                post_local--;
                post_bookmarks--;
                post_folders--;
                search_results_model.remove (i);
            }
        }
    }

    private void refine_bookmarks_results (string term)
    {
        for (int i = post_bookmarks - 1; i >= post_local; i--)
        {
            SettingObject item = (SettingObject) search_results_model.get_item (i);
            if (!(term in item.name))
            {
                post_bookmarks--;
                post_folders--;
                search_results_model.remove (i);
            }
        }
    }

    private void refine_global_results (string term)
    {
        for (int i = (int) search_results_model.get_n_items () - 1; i >= post_folders; i--)
        {
            SettingObject item = (SettingObject) search_results_model.get_item (i);
            if (!(term in item.name))
                search_results_model.remove (i);
        }
        for (int i = post_folders - 1; i >= post_local; i--)
        {
            SettingObject item = (SettingObject) search_results_model.get_item (i);
            if (!(term in item.name))
            {
                post_folders--;
                search_results_model.remove (i);
            }
        }
    }

    private bool local_search (SettingsModel model, string current_path, string term)
    {
        SettingComparator comparator = browser_view.sorting_options.get_comparator ();
        GLib.CompareDataFunc compare = (a, b) => comparator.compare((SettingObject) a, (SettingObject) b);

        if (current_path.has_suffix ("/"))
        {
            Directory? local = model.get_directory (current_path);
            if (local != null)
            {
                GLib.ListStore key_model = ((!) local).key_model;
                for (uint i = 0; i < key_model.get_n_items (); i++)
                {
                    SettingObject item = (SettingObject) key_model.get_item (i);
                    if (term in item.name)
                        search_results_model.insert_sorted (item, compare);
                }
            }
        }
        post_local = (int) search_results_model.get_n_items ();
        post_bookmarks = post_local;
        post_folders = post_local;

        if (term == "")
            return false;
        return true;
    }

    private bool bookmark_search (SettingsModel model, string current_path, string term)
    {
        string [] installed_bookmarks = {}; // TODO move check in Bookmarks
        foreach (string bookmark in window.get_bookmarks ())
        {
            if (bookmark in installed_bookmarks)
                continue;
            installed_bookmarks += bookmark;

            if (bookmark == current_path)
                continue;
            if (model.get_parent_path (bookmark) == current_path)
                continue;

            SettingObject? setting_object = model.get_object (bookmark);
            if (setting_object == null)
                continue;

            if (term in ((!) setting_object).name)
            {
                post_bookmarks++;
                post_folders++;
                search_results_model.insert (post_bookmarks - 1, (!) setting_object);
            }
        }

        return true;
    }

    private void stop_global_search ()
    {
        pause_global_search ();
        search_nodes.clear ();
    }

    private void start_global_search (SettingsModel model, string current_path, string term)
    {
        search_nodes.push_head ((!) model.get_directory ("/"));
        resume_global_search (current_path, term);
    }

    private void pause_global_search ()
    {
        if (search_source == null)
            return;
        Source.remove ((!) search_source);
        search_source = null;
    }

    private void resume_global_search (string current_path, string term)
    {
        search_source = Idle.add (() => {
                if (global_search_step (current_path, term))
                    return true;
                search_source = null;
                return false;
            });
    }

    private bool global_search_step (string current_path, string term)
    {
        if (!search_nodes.is_empty ())
        {
            Directory next = (!) search_nodes.pop_head ();
            bool local_again = next.full_name == current_path;

            GLib.ListStore next_key_model = next.key_model;
            for (uint i = 0; i < next_key_model.get_n_items (); i++)
            {
                SettingObject item = (SettingObject) next_key_model.get_item (i);
                if (item is Directory)
                {
                    if (!local_again && term in item.name)
                        search_results_model.insert (post_folders++, item);
                    search_nodes.push_tail ((Directory) item); // we still search local children
                }
                else
                {
                    if (!local_again && term in item.name)
                        search_results_model.append (item);
                }
            }

            ensure_selection ();

            return true;
        }

        return false;
    }

    private void update_search_results_header (ListBoxRow row, ListBoxRow? before)
    {
        string? label_text = null;
        if (before == null && post_local > 0)
            label_text = _("Current folder");
        else if (row.get_index () == post_local && post_local != post_bookmarks)
            label_text = _("Bookmarks");
        else if (row.get_index () == post_bookmarks && post_bookmarks != post_folders)
            label_text = _("Folders");
        else if (row.get_index () == post_folders)
            label_text = _("Keys");

        ListBoxRowHeader header = new ListBoxRowHeader (before == null, label_text);
        row.set_header (header);
    }
}
