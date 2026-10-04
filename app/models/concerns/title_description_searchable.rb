# Case-insensitive substring search over title and description, ranked so
# titles starting with the term come first, then titles with a word starting
# with it, then everything else, with `then_order` breaking ties. The term is
# only ever passed as a bound value, and LIKE wildcards in it (% and _) are
# escaped so they match literally.
module TitleDescriptionSearchable
  extend ActiveSupport::Concern

  class_methods do
    def search_ranked(term, then_order:)
      pattern = sanitize_sql_like(term.to_s)
      title = "#{quoted_table_name}.title"
      description = "#{quoted_table_name}.description"

      rank_sql = sanitize_sql_array([
        "CASE WHEN #{title} ILIKE ? THEN 1 WHEN #{title} ILIKE ? THEN 2 ELSE 3 END",
        "#{pattern}%",
        "% #{pattern}%"
      ])

      where("#{title} ILIKE :contains OR #{description} ILIKE :contains", contains: "%#{pattern}%")
        .order(Arel.sql(rank_sql), Arel.sql(then_order))
    end
  end
end
