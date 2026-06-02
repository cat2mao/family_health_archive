package com.familyhealth.archive.widget

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.familyhealth.archive.R
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class ReminderWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ReminderRemoteViewsFactory(applicationContext)
    }
}

class ReminderRemoteViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private var reminders = mutableListOf<WidgetItem>()

    data class WidgetItem(
        val title: String,
        val subtitle: String,
        val time: String,
        val type: String
    )

    override fun onCreate() {}

    override fun onDataSetChanged() {
        reminders.clear()
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val jsonStr = prefs.getString("flutter.widget_reminders", null)
            if (jsonStr != null) {
                val array = JSONArray(jsonStr)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    reminders.add(
                        WidgetItem(
                            title = obj.optString("title", ""),
                            subtitle = obj.optString("subtitle", ""),
                            time = obj.optString("time", ""),
                            type = obj.optString("type", "custom")
                        )
                    )
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        reminders.clear()
    }

    override fun getCount(): Int = reminders.size

    override fun getViewAt(position: Int): RemoteViews {
        val item = reminders[position]
        val views = RemoteViews(context.packageName, R.layout.reminder_widget_list_item)

        views.setTextViewText(R.id.item_title, item.title)
        views.setTextViewText(R.id.item_subtitle, item.subtitle)
        views.setTextViewText(R.id.item_time, item.time)

        // Set icon based on type
        val iconRes = when (item.type) {
            "medication" -> android.R.drawable.ic_menu_agenda
            "recheck" -> android.R.drawable.ic_menu_recent_history
            "vaccination" -> android.R.drawable.ic_menu_add
            "deworming" -> android.R.drawable.ic_menu_close_clear_cancel
            else -> android.R.drawable.ic_popup_reminder
        }
        views.setImageViewResource(R.id.item_icon, iconRes)

        // Set fill-in intent for item click
        val fillInIntent = Intent().apply {
            putExtra("reminder_title", item.title)
        }
        views.setOnClickFillInIntent(R.id.item_icon, fillInIntent)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
