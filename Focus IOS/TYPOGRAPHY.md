# Focus iOS — Typography Spec

> Approved specs are marked with **LOCKED**. Do not change without explicit approval.

## Home Screen

### Profile Header — Day Name
| Property     | Value                |
|-------------|----------------------|
| Font        | Helvetica Neue       |
| Weight      | Regular              |
| Size        | 34.6pt               |
| Tracking    | -0.36                |
| Line height | 36                   |
| Color       | `.primary`           |

### Profile Header — Date
| Property     | Value                |
|-------------|----------------------|
| Font        | Helvetica Neue       |
| Weight      | Regular              |
| Size        | 17.3pt               |
| Tracking    | -0.18                |
| Line height | 20                   |
| Color       | #262626              |

### Card Title (Inbox, Today, Someday, etc.) — LOCKED
| Property     | Value                |
|-------------|----------------------|
| Font        | Helvetica Neue       |
| Weight      | Regular              |
| Size        | 15.22pt              |
| Tracking    | -0.158               |
| Color       | #262626              |

### Card Count Badge
| Property     | Value                |
|-------------|----------------------|
| Font        | Helvetica Neue       |
| Weight      | Regular              |
| Size        | 11.08pt              |
| Tracking    | -0.11                |
| Line height | 13.4                 |
| Color       | `.secondary`         |

### Card Icon
| Property     | Value                |
|-------------|----------------------|
| Font        | Helvetica Neue       |
| Weight      | Regular              |
| Size        | 17.3pt               |
| Color       | #262626              |

### Section Divider Labels (LIBRARY, PINNED, CATEGORIES)
| Property     | Value                |
|-------------|----------------------|
| Font        | Fragment Mono        |
| Weight      | Regular              |
| Size        | 13.3pt               |
| Tracking    | 0.624                |
| Line height | 15.96                |
| Color       | #262626              |

### Section Divider Line
| Property     | Value                       |
|-------------|-----------------------------|
| Height      | 1pt                         |
| Color       | `.secondary` at 30% opacity |

---

## Colors

| Token        | Value     | Usage                              |
|-------------|-----------|------------------------------------|
| #262626     | Dark gray | Card titles, icons, date, sections |
| `.primary`  | System    | Day name                           |
| `.secondary`| System    | Count badges, divider lines        |

---

## Fonts Used

| Font             | Where                        |
|-----------------|------------------------------|
| Helvetica Neue  | Home cards, profile header   |
| Fragment Mono   | Section divider labels       |
| Inter            | Other screens (default)      |
| Montserrat      | Date navigator               |
| GolosText       | Focus/extra section headers  |
