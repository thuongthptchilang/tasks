-- =============================================================================
-- CỔNG ĐIỀU HÀNH THPT CHI LĂNG - DATABASE SCHEMA (SUPABASE / POSTGRESQL)
-- Phiên bản: V1.0 Production
-- Bao gồm: Extensions, Enums, Bảng, Indexes, Helper Functions (Security Definer),
--          Triggers tự động, RLS Policies nghiêm ngặt, Storage Policies, Seed Data.
-- =============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- 2. ENUMS (Xóa nếu tồn tại hoặc tạo mới an toàn)
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
        CREATE TYPE public.app_role AS ENUM (
            'super_admin',      -- Quản trị hệ thống (ADMIN)
            'admin',            -- Ban Giám Hiệu (BGH)
            'accountant',       -- Kế toán (KẾ TOÁN)
            'department_head',  -- Tổ trưởng chuyên môn (TỔ TRƯỞNG)
            'youth_union',      -- Đoàn Thanh niên (ĐOÀN TN)
            'teacher'           -- Giáo viên / Nhân viên (GIÁO VIÊN)
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'announcement_priority') THEN
        CREATE TYPE public.announcement_priority AS ENUM (
            'normal',
            'important',
            'urgent'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
        CREATE TYPE public.task_status AS ENUM (
            'pending',
            'in_progress',
            'completed',
            'overdue',
            'cancelled'
        );
    END IF;
END$$;

-- =============================================================================
-- 3. TABLES (11 BẢNG CHUẨN)
-- =============================================================================

-- 3.1. Bảng departments (Phòng ban / Tổ chuyên môn)
CREATE TABLE IF NOT EXISTS public.departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.2. Bảng profiles (Hồ sơ người dùng liên kết với auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    avatar_url TEXT,
    role public.app_role NOT NULL DEFAULT 'teacher',
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    position TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.3. Bảng school_settings (Cấu hình thông tin trường)
CREATE TABLE IF NOT EXISTS public.school_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_name TEXT DEFAULT 'Trường THPT Chi Lăng',
    school_logo TEXT,
    school_address TEXT DEFAULT 'THPT Chi Lăng',
    school_phone TEXT DEFAULT '024.xxxx.xxxx',
    academic_year TEXT DEFAULT '2026 - 2027',
    timezone TEXT DEFAULT 'Asia/Ho_Chi_Minh',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.4. Bảng categories (Danh mục phân loại thông báo)
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,
    icon TEXT DEFAULT 'fa-bullhorn',
    color TEXT DEFAULT '#1d4ed8',
    is_active BOOLEAN DEFAULT TRUE
);

-- 3.5. Bảng announcements (Bảng trung tâm: Thông báo hành chính)
-- Lưu ý:
-- target_type nhận các giá trị: 'all' | 'department' | 'role' | 'selected'
-- target_department_id, target_role, target_user_ids bổ trợ cho trigger tự động phân phối
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'HANH_CHINH',
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('normal', 'important', 'urgent')),
    sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    target_type TEXT DEFAULT 'all' CHECK (target_type IN ('all', 'department', 'role', 'selected')),
    target_department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    target_role public.app_role,
    target_user_ids UUID[] DEFAULT '{}',
    publish_at TIMESTAMPTZ DEFAULT NOW(),
    deadline TIMESTAMPTZ,
    is_published BOOLEAN DEFAULT TRUE,
    is_pinned BOOLEAN DEFAULT FALSE,
    attachment_url TEXT,
    attachment_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.6. Bảng announcement_recipients (Danh sách người nhận & trạng thái đọc/xác nhận/hoàn thành)
CREATE TABLE IF NOT EXISTS public.announcement_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id UUID NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(announcement_id, user_id)
);

-- 3.7. Bảng tasks (Quản lý công việc)
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('normal', 'important', 'urgent')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'overdue', 'cancelled')),
    start_date TIMESTAMPTZ DEFAULT NOW(),
    deadline TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.8. Bảng task_assignees (Phân công người thực hiện công việc)
CREATE TABLE IF NOT EXISTS public.task_assignees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'overdue', 'cancelled')),
    completed_at TIMESTAMPTZ,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(task_id, user_id)
);

-- 3.9. Bảng attachments (Quản lý tệp đính kèm chi tiết)
CREATE TABLE IF NOT EXISTS public.attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id UUID REFERENCES public.announcements(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT DEFAULT 0,
    mime_type TEXT,
    uploaded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.10. Bảng notifications (Thông báo chuông nội bộ Realtime)
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT,
    type TEXT DEFAULT 'announcement',
    reference_id UUID,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.11. Bảng activity_logs (Nhật ký hoạt động hệ thống)
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT,
    entity_id UUID,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 4. INDEXES TỐI ƯU HIỆU NĂNG TRUY VẤN
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_department ON public.profiles(department_id);
CREATE INDEX IF NOT EXISTS idx_announcements_sender ON public.announcements(sender_id);
CREATE INDEX IF NOT EXISTS idx_announcements_department ON public.announcements(department_id);
CREATE INDEX IF NOT EXISTS idx_announcements_publish_at ON public.announcements(publish_at DESC);
CREATE INDEX IF NOT EXISTS idx_announcements_priority ON public.announcements(priority);
CREATE INDEX IF NOT EXISTS idx_ann_recipients_user ON public.announcement_recipients(user_id);
CREATE INDEX IF NOT EXISTS idx_ann_recipients_announcement ON public.announcement_recipients(announcement_id);
CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON public.tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_tasks_department ON public.tasks(department_id);
CREATE INDEX IF NOT EXISTS idx_tasks_deadline ON public.tasks(deadline);
CREATE INDEX IF NOT EXISTS idx_task_assignees_user ON public.task_assignees(user_id);
CREATE INDEX IF NOT EXISTS idx_task_assignees_task ON public.task_assignees(task_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON public.notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created ON public.activity_logs(created_at DESC);

-- =============================================================================
-- 5. HELPER FUNCTIONS (SECURITY DEFINER - TRÁNH INFINITE RECURSION TRONG RLS)
-- =============================================================================

-- Lấy role hiện tại của user đang đăng nhập (chỉ trả về nếu tài khoản is_active = TRUE)
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid() AND is_active = TRUE;
$$;

-- Lấy department_id hiện tại của user đang đăng nhập
CREATE OR REPLACE FUNCTION public.current_user_department()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT department_id FROM public.profiles WHERE id = auth.uid() AND is_active = TRUE;
$$;

-- Kiểm tra có phải Super Admin (ADMIN hệ thống) không
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND is_active = TRUE AND role = 'super_admin'
    );
$$;

-- Kiểm tra có phải nhóm Quản trị toàn trường (ADMIN hoặc BGH) không
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND is_active = TRUE AND role IN ('super_admin', 'admin')
    );
$$;

-- Kiểm tra có phải Tổ trưởng chuyên môn không
CREATE OR REPLACE FUNCTION public.is_department_head()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND is_active = TRUE AND role = 'department_head'
    );
$$;

-- Kiểm tra có phải Kế toán không
CREATE OR REPLACE FUNCTION public.is_accountant()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND is_active = TRUE AND role = 'accountant'
    );
$$;

-- Kiểm tra có phải Đoàn Thanh niên không
CREATE OR REPLACE FUNCTION public.is_youth_union()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND is_active = TRUE AND role = 'youth_union'
    );
$$;

-- Kiểm tra user hiện tại có phải người nhận của thông báo không (SECURITY DEFINER để tránh lặp RLS)
CREATE OR REPLACE FUNCTION public.is_announcement_recipient(p_announcement_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.announcement_recipients
        WHERE announcement_id = p_announcement_id AND user_id = auth.uid()
    );
$$;

-- Kiểm tra user hiện tại có phải người gửi hoặc trưởng đơn vị của thông báo không
CREATE OR REPLACE FUNCTION public.can_view_announcement_tracking(p_announcement_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.announcements a
        WHERE a.id = p_announcement_id
          AND (
              public.is_admin()
              OR a.sender_id = auth.uid()
              OR (
                  public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
                  AND a.department_id = public.current_user_department()
              )
          )
    );
$$;

-- Kiểm tra user hiện tại có được giao task này không
CREATE OR REPLACE FUNCTION public.is_task_assignee(p_task_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.task_assignees
        WHERE task_id = p_task_id AND user_id = auth.uid()
    );
$$;

-- Kiểm tra user hiện tại có quyền quản lý task này không
CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = p_task_id
          AND (
              public.is_admin()
              OR t.created_by = auth.uid()
              OR (
                  public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
                  AND t.department_id = public.current_user_department()
              )
          )
    );
$$;

-- =============================================================================
-- 6. TRIGGERS & AUTOMATION FUNCTIONS
-- =============================================================================

-- 6.1. Trigger tự động cập nhật updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_profiles_updated_at ON public.profiles;
CREATE TRIGGER tr_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS tr_announcements_updated_at ON public.announcements;
CREATE TRIGGER tr_announcements_updated_at
    BEFORE UPDATE ON public.announcements
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS tr_tasks_updated_at ON public.tasks;
CREATE TRIGGER tr_tasks_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 6.2. Trigger bảo vệ bảng profiles: Không cho phép user thường tự nâng quyền (role), đổi phòng ban hoặc mở khóa
CREATE OR REPLACE FUNCTION public.protect_profile_sensitive_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Nếu gọi từ SQL Editor / Postgres Role (auth.uid() IS NULL) hoặc người gọi là ADMIN/BGH thì cho phép
    IF auth.uid() IS NULL OR public.is_admin() THEN
        -- Tuy nhiên nếu là BGH ('admin') thì không được nâng ai lên 'super_admin' hoặc sửa 'super_admin'
        IF auth.uid() IS NOT NULL AND NOT public.is_super_admin() THEN
            IF NEW.role = 'super_admin' OR OLD.role = 'super_admin' THEN
                RAISE EXCEPTION 'Chỉ Quản trị hệ thống (ADMIN) mới có quyền thay đổi tài khoản Super Admin.';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    -- Đối với người dùng thông thường tự sửa profile của chính mình:
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        RAISE EXCEPTION 'Bảo mật: Bạn không có quyền tự thay đổi vai trò (role) của mình!';
    END IF;

    IF NEW.department_id IS DISTINCT FROM OLD.department_id THEN
        RAISE EXCEPTION 'Bảo mật: Bạn không có quyền tự thay đổi đơn vị công tác!';
    END IF;

    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
        RAISE EXCEPTION 'Bảo mật: Bạn không có quyền tự thay đổi trạng thái kích hoạt tài khoản!';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_protect_profile_columns ON public.profiles;
CREATE TRIGGER tr_protect_profile_columns
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.protect_profile_sensitive_columns();

-- 6.3. Trigger tự động tạo bản ghi `profiles` khi có user mới đăng ký trong `auth.users`
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_full_name TEXT;
    v_default_dept UUID;
BEGIN
    v_full_name := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        split_part(COALESCE(NEW.email, 'Giao vien'), '@', 1)
    );

    INSERT INTO public.profiles (id, full_name, email, phone, role, department_id, position, is_active)
    VALUES (
        NEW.id,
        v_full_name,
        NEW.email,
        NEW.raw_user_meta_data->>'phone',
        'teacher', -- Luôn mặc định là teacher để đảm bảo an toàn tuyệt đối
        v_default_dept,
        COALESCE(NEW.raw_user_meta_data->>'position', 'Giáo viên'),
        TRUE
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- 6.4. Trigger tự động tạo `announcement_recipients` và `notifications` khi thông báo được đăng (publish)
CREATE OR REPLACE FUNCTION public.distribute_announcement_recipients()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient RECORD;
    v_target_dept UUID;
    v_should_distribute BOOLEAN := FALSE;
BEGIN
    -- Chỉ phân phối khi thông báo ở trạng thái is_published = TRUE
    IF TG_OP = 'INSERT' AND NEW.is_published = TRUE THEN
        v_should_distribute := TRUE;
    ELSIF TG_OP = 'UPDATE' AND NEW.is_published = TRUE AND COALESCE(OLD.is_published, FALSE) = FALSE THEN
        v_should_distribute := TRUE;
    END IF;

    IF NOT v_should_distribute THEN
        RETURN NEW;
    END IF;

    v_target_dept := COALESCE(NEW.target_department_id, NEW.department_id);

    -- Lặp qua danh sách user active thỏa mãn target_type
    FOR v_recipient IN
        SELECT p.id AS user_id
        FROM public.profiles p
        WHERE p.is_active = TRUE
          AND (
              (NEW.target_type = 'all')
              OR (NEW.target_type = 'department' AND p.department_id = v_target_dept)
              OR (NEW.target_type = 'role' AND p.role = NEW.target_role)
              OR (NEW.target_type = 'selected' AND p.id = ANY(COALESCE(NEW.target_user_ids, '{}')))
          )
    LOOP
        -- 1. Tạo bản ghi người nhận
        INSERT INTO public.announcement_recipients (announcement_id, user_id, read_at)
        VALUES (
            NEW.id,
            v_recipient.user_id,
            CASE WHEN v_recipient.user_id = NEW.sender_id THEN NOW() ELSE NULL END
        )
        ON CONFLICT (announcement_id, user_id) DO NOTHING;

        -- 2. Tạo thông báo chuông nội bộ (trừ chính người gửi)
        IF v_recipient.user_id IS DISTINCT FROM NEW.sender_id THEN
            INSERT INTO public.notifications (user_id, title, message, type, reference_id, is_read)
            VALUES (
                v_recipient.user_id,
                CASE
                    WHEN NEW.priority = 'urgent' THEN '[KHẨN] ' || NEW.title
                    WHEN NEW.priority = 'important' THEN '[QUAN TRỌNG] ' || NEW.title
                    ELSE 'Thông báo mới: ' || NEW.title
                END,
                LEFT(REGEXP_REPLACE(NEW.content, '\s+', ' ', 'g'), 140),
                'announcement',
                NEW.id,
                FALSE
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_distribute_announcement ON public.announcements;
CREATE TRIGGER tr_distribute_announcement
    AFTER INSERT OR UPDATE ON public.announcements
    FOR EACH ROW EXECUTE FUNCTION public.distribute_announcement_recipients();

-- 6.5. Trigger tự động tạo `notifications` khi giao công việc mới (`task_assignees`)
CREATE OR REPLACE FUNCTION public.notify_task_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_task RECORD;
BEGIN
    SELECT id, title, deadline, created_by INTO v_task
    FROM public.tasks
    WHERE id = NEW.task_id;

    IF v_task.id IS NOT NULL AND NEW.user_id IS DISTINCT FROM v_task.created_by THEN
        INSERT INTO public.notifications (user_id, title, message, type, reference_id, is_read)
        VALUES (
            NEW.user_id,
            'Công việc mới: ' || v_task.title,
            CASE
                WHEN v_task.deadline IS NOT NULL THEN 'Hạn hoàn thành: ' || to_char(v_task.deadline AT TIME ZONE 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
                ELSE 'Bạn vừa được phân công một công việc mới trên Cổng điều hành.'
            END,
            'task',
            v_task.id,
            FALSE
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_task_assigned ON public.task_assignees;
CREATE TRIGGER tr_notify_task_assigned
    AFTER INSERT ON public.task_assignees
    FOR EACH ROW EXECUTE FUNCTION public.notify_task_assigned();

-- 6.6. Trigger đồng bộ trạng thái `tasks` khi tất cả `task_assignees` hoàn thành
CREATE OR REPLACE FUNCTION public.sync_parent_task_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total INT;
    v_completed INT;
    v_in_progress INT;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'completed'),
        COUNT(*) FILTER (WHERE status = 'in_progress')
    INTO v_total, v_completed, v_in_progress
    FROM public.task_assignees
    WHERE task_id = NEW.task_id;

    IF v_total > 0 AND v_completed = v_total THEN
        UPDATE public.tasks SET status = 'completed', updated_at = NOW() WHERE id = NEW.task_id AND status <> 'completed';
    ELSIF v_in_progress > 0 OR v_completed > 0 THEN
        UPDATE public.tasks SET status = 'in_progress', updated_at = NOW() WHERE id = NEW.task_id AND status = 'pending';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_sync_parent_task_status ON public.task_assignees;
CREATE TRIGGER tr_sync_parent_task_status
    AFTER UPDATE OF status ON public.task_assignees
    FOR EACH ROW EXECUTE FUNCTION public.sync_parent_task_status();

-- =============================================================================
-- 7. ROW LEVEL SECURITY (RLS) - BẢO MẬT TUYỆT ĐỐI CHO TẤT CẢ 11 BẢNG
-- =============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_assignees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 7.1. Policies cho `departments`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "departments_select_authenticated" ON public.departments;
CREATE POLICY "departments_select_authenticated"
    ON public.departments FOR SELECT
    TO authenticated
    USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "departments_admin_all" ON public.departments;
CREATE POLICY "departments_admin_all"
    ON public.departments FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- -----------------------------------------------------------------------------
-- 7.2. Policies cho `school_settings`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "school_settings_select_all" ON public.school_settings;
CREATE POLICY "school_settings_select_all"
    ON public.school_settings FOR SELECT
    TO anon, authenticated
    USING (school_name IS NOT NULL);

DROP POLICY IF EXISTS "school_settings_admin_write" ON public.school_settings;
CREATE POLICY "school_settings_admin_write"
    ON public.school_settings FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- -----------------------------------------------------------------------------
-- 7.3. Policies cho `categories`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "categories_select_authenticated" ON public.categories;
CREATE POLICY "categories_select_authenticated"
    ON public.categories FOR SELECT
    TO authenticated
    USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "categories_admin_all" ON public.categories;
CREATE POLICY "categories_admin_all"
    ON public.categories FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- -----------------------------------------------------------------------------
-- 7.4. Policies cho `profiles`
-- -----------------------------------------------------------------------------
-- Người dùng đã đăng nhập (active) có thể xem thông tin cơ bản của đồng nghiệp để hiển thị tên người gửi/giao việc
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
CREATE POLICY "profiles_select_authenticated"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (auth.uid() IS NOT NULL);

-- Người dùng chỉ được tạo profile của chính mình
DROP POLICY IF EXISTS "profiles_insert_self_or_admin" ON public.profiles;
CREATE POLICY "profiles_insert_self_or_admin"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (id = auth.uid() OR public.is_admin());

-- Người dùng được sửa thông tin cá nhân của mình (Trigger đã chặn sửa role/department_id/is_active)
-- ADMIN và BGH được sửa tất cả profiles
DROP POLICY IF EXISTS "profiles_update_self_or_admin" ON public.profiles;
CREATE POLICY "profiles_update_self_or_admin"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid() OR public.is_admin())
    WITH CHECK (id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "profiles_delete_super_admin" ON public.profiles;
CREATE POLICY "profiles_delete_super_admin"
    ON public.profiles FOR DELETE
    TO authenticated
    USING (public.is_super_admin());

-- -----------------------------------------------------------------------------
-- 7.5. Policies cho `announcements`
-- -----------------------------------------------------------------------------
-- SELECT:
-- 1. ADMIN / BGH: Xem toàn bộ
-- 2. Người tạo (sender_id = auth.uid()): Xem thông báo mình tạo (kể cả bản nháp)
-- 3. TỔ TRƯỞNG / KẾ TOÁN / ĐOÀN TN: Xem thông báo thuộc đơn vị mình
-- 4. GIÁO VIÊN & TẤT CẢ USER: Chỉ xem thông báo đã phát hành (is_published = TRUE) mà mình nằm trong announcement_recipients hoặc target_type = 'all'
DROP POLICY IF EXISTS "announcements_select_policy" ON public.announcements;
CREATE POLICY "announcements_select_policy"
    ON public.announcements FOR SELECT
    TO authenticated
    USING (
        public.is_admin()
        OR sender_id = auth.uid()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND department_id = public.current_user_department()
        )
        OR (
            is_published = TRUE
            AND (
                target_type = 'all'
                OR public.is_announcement_recipient(id)
            )
        )
    );

-- INSERT:
-- 1. ADMIN / BGH: Tạo mọi thông báo
-- 2. TỔ TRƯỞNG / KẾ TOÁN / ĐOÀN TN: Được tạo thông báo trong phạm vi đơn vị của mình (sender_id = auth.uid() và department_id = current_user_department())
-- 3. GIÁO VIÊN: Không được tạo thông báo
DROP POLICY IF EXISTS "announcements_insert_policy" ON public.announcements;
CREATE POLICY "announcements_insert_policy"
    ON public.announcements FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND sender_id = auth.uid()
            AND department_id = public.current_user_department()
        )
    );

-- UPDATE:
-- 1. ADMIN / BGH: Sửa mọi thông báo
-- 2. KẾ TOÁN / TỔ TRƯỞNG / ĐOÀN TN: Chỉ sửa thông báo do mình tạo hoặc thuộc đơn vị mình (không được sửa thông báo của BGH)
DROP POLICY IF EXISTS "announcements_update_policy" ON public.announcements;
CREATE POLICY "announcements_update_policy"
    ON public.announcements FOR UPDATE
    TO authenticated
    USING (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND sender_id = auth.uid()
        )
    )
    WITH CHECK (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND sender_id = auth.uid()
            AND department_id = public.current_user_department()
        )
    );

-- DELETE:
-- 1. ADMIN / BGH: Xóa mọi thông báo
-- 2. KẾ TOÁN / TỔ TRƯỞNG / ĐOÀN TN: Chỉ xóa thông báo do chính mình tạo (không thể xóa thông báo của BGH)
DROP POLICY IF EXISTS "announcements_delete_policy" ON public.announcements;
CREATE POLICY "announcements_delete_policy"
    ON public.announcements FOR DELETE
    TO authenticated
    USING (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND sender_id = auth.uid()
        )
    );

-- -----------------------------------------------------------------------------
-- 7.6. Policies cho `announcement_recipients`
-- -----------------------------------------------------------------------------
-- SELECT:
-- 1. Người nhận chỉ xem bản ghi của chính mình (user_id = auth.uid())
-- 2. ADMIN / BGH / Người gửi thông báo / Trưởng bộ phận có thông báo: Xem danh sách ai đã đọc / chưa đọc
DROP POLICY IF EXISTS "announcement_recipients_select_policy" ON public.announcement_recipients;
CREATE POLICY "announcement_recipients_select_policy"
    ON public.announcement_recipients FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid()
        OR public.can_view_announcement_tracking(announcement_id)
    );

-- INSERT:
-- Cho phép người gửi thông báo, Admin hoặc bản thân user (khi thông báo là 'all') khởi tạo bản ghi nhận
DROP POLICY IF EXISTS "announcement_recipients_insert_policy" ON public.announcement_recipients;
CREATE POLICY "announcement_recipients_insert_policy"
    ON public.announcement_recipients FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_admin()
        OR public.can_view_announcement_tracking(announcement_id)
        OR user_id = auth.uid()
    );

-- UPDATE:
-- Giáo viên / người nhận chỉ được UPDATE read_at, confirmed_at, completed_at trên dòng của chính mình
DROP POLICY IF EXISTS "announcement_recipients_update_own" ON public.announcement_recipients;
CREATE POLICY "announcement_recipients_update_own"
    ON public.announcement_recipients FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid() OR public.is_admin())
    WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "announcement_recipients_delete_admin" ON public.announcement_recipients;
CREATE POLICY "announcement_recipients_delete_admin"
    ON public.announcement_recipients FOR DELETE
    TO authenticated
    USING (public.is_admin() OR public.can_view_announcement_tracking(announcement_id));

-- -----------------------------------------------------------------------------
-- 7.7. Policies cho `tasks`
-- -----------------------------------------------------------------------------
-- SELECT:
-- 1. ADMIN / BGH: Xem toàn bộ công việc
-- 2. Người tạo công việc (created_by = auth.uid())
-- 3. TỔ TRƯỞNG / KẾ TOÁN / ĐOÀN TN: Xem công việc thuộc đơn vị của mình
-- 4. GIÁO VIÊN: Xem công việc mà mình được giao (nằm trong task_assignees) hoặc công việc chung của tổ mình
DROP POLICY IF EXISTS "tasks_select_policy" ON public.tasks;
CREATE POLICY "tasks_select_policy"
    ON public.tasks FOR SELECT
    TO authenticated
    USING (
        public.is_admin()
        OR created_by = auth.uid()
        OR public.is_task_assignee(id)
        OR (
            department_id IS NOT NULL
            AND department_id = public.current_user_department()
        )
    );

-- INSERT:
-- ADMIN, BGH, KẾ TOÁN, TỔ TRƯỞNG, ĐOÀN TN được tạo công việc
DROP POLICY IF EXISTS "tasks_insert_policy" ON public.tasks;
CREATE POLICY "tasks_insert_policy"
    ON public.tasks FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND created_by = auth.uid()
            AND department_id = public.current_user_department()
        )
    );

-- UPDATE:
-- Người quản lý task hoặc người được giao task (để cập nhật trạng thái)
DROP POLICY IF EXISTS "tasks_update_policy" ON public.tasks;
CREATE POLICY "tasks_update_policy"
    ON public.tasks FOR UPDATE
    TO authenticated
    USING (
        public.can_manage_task(id)
        OR public.is_task_assignee(id)
    )
    WITH CHECK (
        public.can_manage_task(id)
        OR public.is_task_assignee(id)
    );

-- DELETE:
-- Chỉ ADMIN/BGH hoặc người tạo ra task mới được xóa
DROP POLICY IF EXISTS "tasks_delete_policy" ON public.tasks;
CREATE POLICY "tasks_delete_policy"
    ON public.tasks FOR DELETE
    TO authenticated
    USING (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND created_by = auth.uid()
        )
    );

-- -----------------------------------------------------------------------------
-- 7.8. Policies cho `task_assignees`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "task_assignees_select_policy" ON public.task_assignees;
CREATE POLICY "task_assignees_select_policy"
    ON public.task_assignees FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid()
        OR public.can_manage_task(task_id)
    );

DROP POLICY IF EXISTS "task_assignees_insert_policy" ON public.task_assignees;
CREATE POLICY "task_assignees_insert_policy"
    ON public.task_assignees FOR INSERT
    TO authenticated
    WITH CHECK (
        public.can_manage_task(task_id)
    );

DROP POLICY IF EXISTS "task_assignees_update_policy" ON public.task_assignees;
CREATE POLICY "task_assignees_update_policy"
    ON public.task_assignees FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid()
        OR public.can_manage_task(task_id)
    )
    WITH CHECK (
        user_id = auth.uid()
        OR public.can_manage_task(task_id)
    );

DROP POLICY IF EXISTS "task_assignees_delete_policy" ON public.task_assignees;
CREATE POLICY "task_assignees_delete_policy"
    ON public.task_assignees FOR DELETE
    TO authenticated
    USING (
        public.can_manage_task(task_id)
    );

-- -----------------------------------------------------------------------------
-- 7.9. Policies cho `attachments`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "attachments_select_policy" ON public.attachments;
CREATE POLICY "attachments_select_policy"
    ON public.attachments FOR SELECT
    TO authenticated
    USING (
        public.is_admin()
        OR uploaded_by = auth.uid()
        OR public.is_announcement_recipient(announcement_id)
        OR public.can_view_announcement_tracking(announcement_id)
    );

DROP POLICY IF EXISTS "attachments_insert_policy" ON public.attachments;
CREATE POLICY "attachments_insert_policy"
    ON public.attachments FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_admin()
        OR (
            public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
            AND uploaded_by = auth.uid()
        )
    );

DROP POLICY IF EXISTS "attachments_delete_policy" ON public.attachments;
CREATE POLICY "attachments_delete_policy"
    ON public.attachments FOR DELETE
    TO authenticated
    USING (
        public.is_admin()
        OR uploaded_by = auth.uid()
    );

-- -----------------------------------------------------------------------------
-- 7.10. Policies cho `notifications`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
CREATE POLICY "notifications_select_own"
    ON public.notifications FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
CREATE POLICY "notifications_update_own"
    ON public.notifications FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_delete_own" ON public.notifications;
CREATE POLICY "notifications_delete_own"
    ON public.notifications FOR DELETE
    TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

-- -----------------------------------------------------------------------------
-- 7.11. Policies cho `activity_logs`
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "activity_logs_select_policy" ON public.activity_logs;
CREATE POLICY "activity_logs_select_policy"
    ON public.activity_logs FOR SELECT
    TO authenticated
    USING (public.is_admin() OR user_id = auth.uid());

DROP POLICY IF EXISTS "activity_logs_insert_policy" ON public.activity_logs;
CREATE POLICY "activity_logs_insert_policy"
    ON public.activity_logs FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- =============================================================================
-- 8. SUPABASE STORAGE: BUCKET `school-documents` & POLICIES
-- =============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'school-documents',
    'school-documents',
    TRUE,
    20971520, -- Giới hạn 20MB / file
    ARRAY[
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'image/jpeg',
        'image/png',
        'image/webp'
    ]
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Policy cho phép người dùng đã đăng nhập xem/tải tài liệu trong bucket school-documents
DROP POLICY IF EXISTS "storage_school_docs_select" ON storage.objects;
CREATE POLICY "storage_school_docs_select"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'school-documents');

-- Policy chỉ cho phép các cấp có quyền tạo thông báo (ADMIN, BGH, KẾ TOÁN, TỔ TRƯỞNG, ĐOÀN TN) tải file lên
DROP POLICY IF EXISTS "storage_school_docs_insert" ON storage.objects;
CREATE POLICY "storage_school_docs_insert"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'school-documents'
        AND (
            public.is_admin()
            OR public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
        )
    );

-- Policy xóa file: Chỉ ADMIN/BGH hoặc chính người đã upload file đó
DROP POLICY IF EXISTS "storage_school_docs_delete" ON storage.objects;
CREATE POLICY "storage_school_docs_delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'school-documents'
        AND (
            public.is_admin()
            OR owner = auth.uid()
        )
    );

-- =============================================================================
-- 9. REALTIME PUBLICATION (Bật Realtime cho Notifications & Announcements)
-- =============================================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.announcement_recipients;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END IF;
END$$;

-- =============================================================================
-- 10. DỮ LIỆU KHỞI TẠO MẪU (SEED DATA CHO PHÒNG BAN, DANH MỤC, CẤU HÌNH TRƯỜNG)
-- =============================================================================

-- 10.1. Phòng ban / Tổ chuyên môn THPT Chi Lăng
INSERT INTO public.departments (name, code, description, is_active)
VALUES
    ('Ban Giám Hiệu', 'BGH', 'Ban Giám Hiệu Trường THPT Chi Lăng - Điều hành chung', TRUE),
    ('Bộ phận Kế toán - Tài vụ', 'KE_TOAN', 'Phụ trách tài chính, chế độ chính sách, lương và học phí', TRUE),
    ('Đoàn Thanh niên', 'DOAN_TN', 'Ban chấp hành Đoàn TNCS Hồ Chí Minh Trường THPT Chi Lăng', TRUE),
    ('Tổ Toán - Hóa - Sinh', 'TO_THS', 'Tổ chuyên môn Toán học, Hóa học, Sinh học', TRUE),
    ('Tổ Lý - Tin - CN - TD - QPAN', 'TO_LTCTQ', 'Tổ chuyên môn Vật lý, Tin học, Công nghệ, Thể dục, QPAN', TRUE),
    ('Tổ Công nghệ', 'TO_CONG_NGHE', 'Bộ phận / Tổ Công nghệ & Chuyển đổi số nhà trường', TRUE),
    ('Tổ Văn - Sử', 'TO_VS', 'Tổ chuyên môn Ngữ văn, Lịch sử', TRUE),
    ('Tổ Anh - Địa - KTPL', 'TO_ADK', 'Tổ chuyên môn Tiếng Anh, Địa lý, Kinh tế & Pháp luật', TRUE),
    ('Tổ Văn phòng', 'TO_VP', 'Tổ Hành chính - Văn thư - Y tế - Thư viện - Bảo vệ', TRUE)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description;

-- 10.2. Danh mục thông báo chuẩn
INSERT INTO public.categories (name, code, icon, color, is_active)
VALUES
    ('Điều hành - BGH', 'DIEU_HANH', 'fa-building-columns', '#1e40af', TRUE),
    ('Chuyên môn - Giảng dạy', 'CHUYEN_MON', 'fa-book-open-reader', '#0284c7', TRUE),
    ('Kế toán - Tài chính', 'TAI_CHINH', 'fa-coins', '#0d9488', TRUE),
    ('Công tác GVCN - Học sinh', 'GVCN', 'fa-users-rectangle', '#7c3aed', TRUE),
    ('Đoàn Thanh niên - Phong trào', 'DOAN_TN', 'fa-flag', '#dc2626', TRUE),
    ('Hành chính - Tổ chức', 'HANH_CHINH', 'fa-file-signature', '#475569', TRUE),
    ('Kiểm tra - Khảo thí', 'KHAO_THI', 'fa-clipboard-check', '#d97706', TRUE)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    icon = EXCLUDED.icon,
    color = EXCLUDED.color;

-- 10.3. Cấu hình trường mặc định
INSERT INTO public.school_settings (school_name, school_logo, school_address, school_phone, academic_year, timezone)
SELECT
    'TRƯỜNG THPT CHI LĂNG',
    'https://ui-avatars.com/api/?name=CL&background=1e40af&color=fff&size=128&bold=true',
    'Trường THPT Chi Lăng',
    '024.3888.9999',
    '2026 - 2027',
    'Asia/Ho_Chi_Minh'
WHERE NOT EXISTS (SELECT 1 FROM public.school_settings);

-- =============================================================================
-- 11. HÀM KHỞI TẠO DỮ LIỆU MẪU NGHIỆP VỤ (CHẠY TỰ ĐỘNG HOẶC KHI ADMIN BẤM NÚT)
-- Vì Supabase không cho phép tạo fake auth.users trực tiếp không an toàn,
-- hàm này cho phép Admin sau khi đăng nhập có thể tạo nhanh dữ liệu thông báo & công việc
-- thực tế của trường THPT Chi Lăng gắn với tài khoản thật hiện có.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.seed_initial_school_data()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_bgh_id UUID;
    v_kt_id UUID;
    v_doan_id UUID;
    v_ann1_id UUID;
    v_ann2_id UUID;
    v_ann3_id UUID;
    v_task1_id UUID;
    v_task2_id UUID;
    v_existing_count INT;
BEGIN
    IF v_uid IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Chỉ Quản trị viên hoặc Ban Giám Hiệu mới có quyền khởi tạo dữ liệu mẫu.';
    END IF;

    SELECT COUNT(*) INTO v_existing_count FROM public.announcements;
    IF v_existing_count > 0 THEN
        RETURN jsonb_build_object('status', 'skipped', 'message', 'Hệ thống đã có dữ liệu thông báo.');
    END IF;

    SELECT id INTO v_bgh_id FROM public.departments WHERE code = 'BGH' LIMIT 1;
    SELECT id INTO v_kt_id FROM public.departments WHERE code = 'KE_TOAN' LIMIT 1;
    SELECT id INTO v_doan_id FROM public.departments WHERE code = 'DOAN_TN' LIMIT 1;

    -- Thông báo 1 (Khẩn - BGH)
    INSERT INTO public.announcements (
        title, content, category, priority, sender_id, department_id, target_type,
        publish_at, deadline, is_published, is_pinned
    ) VALUES (
        'Triển khai kế hoạch kiểm tra giữa học kỳ và nộp ma trận đề kiểm tra',
        E'Kính gửi: Các Tổ trưởng chuyên môn và toàn thể Giáo viên trường THPT Chi Lăng.\n\nThực hiện kế hoạch năm học, Ban Giám Hiệu yêu cầu các tổ chuyên môn:\n1. Họp tổ thống nhất ma trận đề kiểm tra định kỳ các khối 10, 11, 12.\n2. Nộp biên bản họp tổ và đề cương ôn tập về Ban chuyên môn đúng thời hạn.\n3. Giáo viên bộ môn hoàn tất nhập điểm thường xuyên trên hệ thống quản lý điểm trước hạn chót.\n\nĐề nghị các thầy cô nghiêm túc thực hiện và bấm "Tôi đã xác nhận" sau khi nắm rõ kế hoạch.',
        'KHAO_THI', 'urgent', v_uid, v_bgh_id, 'all',
        NOW() - INTERVAL '2 hours', NOW() + INTERVAL '3 days', TRUE, TRUE
    ) RETURNING id INTO v_ann1_id;

    -- Thông báo 2 (Quan trọng - GVCN)
    INSERT INTO public.announcements (
        title, content, category, priority, sender_id, department_id, target_type,
        publish_at, deadline, is_published, is_pinned
    ) VALUES (
        'Rà soát và nộp danh sách học sinh đăng ký BHYT và hồ sơ miễn giảm học phí',
        E'Bộ phận Kế toán - Tài vụ phối hợp với GVCN các lớp thực hiện:\n- Rà soát thông tin mã số BHXH/BHYT của 100% học sinh trong lớp.\n- Lập danh sách học sinh thuộc diện chính sách, hộ nghèo, cận nghèo để làm chế độ hỗ trợ chi phí học tập.\n- Nộp bản tổng hợp có chữ ký của GVCN về phòng Kế toán.',
        'TAI_CHINH', 'important', v_uid, v_kt_id, 'all',
        NOW() - INTERVAL '1 day', NOW() + INTERVAL '2 days', TRUE, FALSE
    ) RETURNING id INTO v_ann2_id;

    -- Thông báo 3 (Thông thường - Đoàn TN)
    INSERT INTO public.announcements (
        title, content, category, priority, sender_id, department_id, target_type,
        publish_at, deadline, is_published, is_pinned
    ) VALUES (
        'Kế hoạch tổ chức sinh hoạt dưới cờ và kiểm tra nền nếp học sinh tuần tới',
        E'Ban Chấp hành Đoàn trường thông báo tới GVCN các lớp:\n- Nhắc nhở học sinh thực hiện nghiêm túc đồng phục, tác phong và an toàn giao thông.\n- Các lớp trực tuần chuẩn bị nội dung chuyên đề sinh hoạt dưới cờ sáng thứ Hai.\n- Đội cờ đỏ tổng hợp điểm thi đua vào 16h30 thứ Bảy hàng tuần.',
        'DOAN_TN', 'normal', v_uid, v_doan_id, 'all',
        NOW() - INTERVAL '2 days', NOW() + INTERVAL '5 days', TRUE, FALSE
    ) RETURNING id INTO v_ann3_id;

    -- Công việc 1
    INSERT INTO public.tasks (
        title, description, created_by, department_id, priority, status, start_date, deadline
    ) VALUES (
        'Nộp danh sách học sinh và hồ sơ BHYT lớp chủ nhiệm',
        'Hoàn thiện biểu mẫu rà soát BHYT của lớp và nộp trực tiếp hoặc đính kèm xác nhận trên hệ thống.',
        v_uid, v_kt_id, 'urgent', 'pending', NOW(), NOW() + INTERVAL '2 days'
    ) RETURNING id INTO v_task1_id;

    INSERT INTO public.task_assignees (task_id, user_id, status, note)
    SELECT v_task1_id, p.id, 'pending', 'Bàn giao từ hệ thống'
    FROM public.profiles p WHERE p.is_active = TRUE
    ON CONFLICT DO NOTHING;

    -- Công việc 2
    INSERT INTO public.tasks (
        title, description, created_by, department_id, priority, status, start_date, deadline
    ) VALUES (
        'Hoàn thành ma trận đề kiểm tra định kỳ và kế hoạch bài dạy tuần tới',
        'Tổ chuyên môn và giáo viên rà soát ma trận đề theo chuẩn chương trình GDPT 2018.',
        v_uid, v_bgh_id, 'important', 'in_progress', NOW() - INTERVAL '1 day', NOW() + INTERVAL '4 days'
    ) RETURNING id INTO v_task2_id;

    INSERT INTO public.task_assignees (task_id, user_id, status, note)
    SELECT v_task2_id, p.id, 'in_progress', 'Đang triển khai tại tổ chuyên môn'
    FROM public.profiles p WHERE p.is_active = TRUE
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object('status', 'success', 'message', 'Đã khởi tạo dữ liệu mẫu thành công.');
END;
$$;

-- =============================================================================
-- 12. NÂNG CẤP BẢN V2.0:
--   (Tính năng 1) Web Push Notifications & Thiết bị đăng ký (`push_subscriptions`)
--   (Tính năng 4) Bình luận & Hỏi đáp trực tiếp dưới Thông báo / Công việc (`comments`)
--   (Tính năng 5) Hỗ trợ Nhập danh sách Giáo viên hàng loạt từ Excel/CSV
--   (Tính năng 6) Phân tích chuyên sâu AI (AI Analytics cho BGH)
-- =============================================================================

-- 12.1. Bảng `comments`: Bình luận & Hỏi đáp trực tiếp dưới Thông báo hoặc Công việc
CREATE TABLE IF NOT EXISTS public.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type TEXT NOT NULL CHECK (entity_type IN ('announcement', 'task')),
    entity_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comments_entity ON public.comments(entity_type, entity_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_comments_user ON public.comments(user_id);

DROP TRIGGER IF EXISTS tr_comments_updated_at ON public.comments;
CREATE TRIGGER tr_comments_updated_at
    BEFORE UPDATE ON public.comments
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 12.2. Bảng `push_subscriptions`: Lưu đăng ký Web Push Notification của thiết bị người dùng
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL,
    p256dh TEXT,
    auth TEXT,
    user_agent TEXT,
    device_label TEXT,
    is_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_push_subs_user ON public.push_subscriptions(user_id, is_enabled);

DROP TRIGGER IF EXISTS tr_push_subs_updated_at ON public.push_subscriptions;
CREATE TRIGGER tr_push_subs_updated_at
    BEFORE UPDATE ON public.push_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 12.3. Helper Function kiểm tra quyền xem/gửi bình luận theo đúng quyền xem Thông báo hoặc Công việc
CREATE OR REPLACE FUNCTION public.can_access_comment_entity(p_entity_type TEXT, p_entity_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN TRUE;
    END IF;

    IF p_entity_type = 'announcement' THEN
        RETURN EXISTS (
            SELECT 1 FROM public.announcements a
            WHERE a.id = p_entity_id
              AND (
                  a.sender_id = auth.uid()
                  OR (
                      public.current_user_role() IN ('department_head', 'accountant', 'youth_union')
                      AND a.department_id = public.current_user_department()
                  )
                  OR (
                      a.is_published = TRUE
                      AND (a.target_type = 'all' OR public.is_announcement_recipient(a.id))
                  )
              )
        );
    ELSIF p_entity_type = 'task' THEN
        RETURN EXISTS (
            SELECT 1 FROM public.tasks t
            WHERE t.id = p_entity_id
              AND (
                  t.created_by = auth.uid()
                  OR public.is_task_assignee(t.id)
                  OR (t.department_id IS NOT NULL AND t.department_id = public.current_user_department())
              )
        );
    END IF;

    RETURN FALSE;
END;
$$;

-- 12.4. Trigger tự động thông báo cho người ban hành thông báo / người giao việc khi có giáo viên hỏi đáp
CREATE OR REPLACE FUNCTION public.notify_on_new_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_commenter_name TEXT;
    v_owner_id UUID;
    v_entity_title TEXT;
BEGIN
    SELECT full_name INTO v_commenter_name FROM public.profiles WHERE id = NEW.user_id;
    v_commenter_name := COALESCE(v_commenter_name, 'Giáo viên');

    IF NEW.entity_type = 'announcement' THEN
        SELECT sender_id, title INTO v_owner_id, v_entity_title
        FROM public.announcements WHERE id = NEW.entity_id;

        IF v_owner_id IS NOT NULL AND v_owner_id IS DISTINCT FROM NEW.user_id THEN
            INSERT INTO public.notifications (user_id, title, message, type, reference_id, is_read)
            VALUES (
                v_owner_id,
                '💬 Hỏi đáp tại thông báo: ' || LEFT(v_entity_title, 70),
                v_commenter_name || ': ' || LEFT(NEW.content, 120),
                'announcement',
                NEW.entity_id,
                FALSE
            );
        END IF;
    ELSIF NEW.entity_type = 'task' THEN
        SELECT created_by, title INTO v_owner_id, v_entity_title
        FROM public.tasks WHERE id = NEW.entity_id;

        IF v_owner_id IS NOT NULL AND v_owner_id IS DISTINCT FROM NEW.user_id THEN
            INSERT INTO public.notifications (user_id, title, message, type, reference_id, is_read)
            VALUES (
                v_owner_id,
                '💬 Trao đổi công việc: ' || LEFT(v_entity_title, 70),
                v_commenter_name || ': ' || LEFT(NEW.content, 120),
                'task',
                NEW.entity_id,
                FALSE
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_on_new_comment ON public.comments;
CREATE TRIGGER tr_notify_on_new_comment
    AFTER INSERT ON public.comments
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_new_comment();

-- 12.5. RLS Policies cho `comments` và `push_subscriptions`
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "comments_select_policy" ON public.comments;
CREATE POLICY "comments_select_policy"
    ON public.comments FOR SELECT
    TO authenticated
    USING (public.can_access_comment_entity(entity_type, entity_id));

DROP POLICY IF EXISTS "comments_insert_policy" ON public.comments;
CREATE POLICY "comments_insert_policy"
    ON public.comments FOR INSERT
    TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND public.can_access_comment_entity(entity_type, entity_id)
    );

DROP POLICY IF EXISTS "comments_update_policy" ON public.comments;
CREATE POLICY "comments_update_policy"
    ON public.comments FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid() OR public.is_admin())
    WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "comments_delete_policy" ON public.comments;
CREATE POLICY "comments_delete_policy"
    ON public.comments FOR DELETE
    TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

-- RLS cho `push_subscriptions`
DROP POLICY IF EXISTS "push_subs_select_own_or_admin" ON public.push_subscriptions;
CREATE POLICY "push_subs_select_own_or_admin"
    ON public.push_subscriptions FOR SELECT
    TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "push_subs_insert_own" ON public.push_subscriptions;
CREATE POLICY "push_subs_insert_own"
    ON public.push_subscriptions FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "push_subs_update_own" ON public.push_subscriptions;
CREATE POLICY "push_subs_update_own"
    ON public.push_subscriptions FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "push_subs_delete_own" ON public.push_subscriptions;
CREATE POLICY "push_subs_delete_own"
    ON public.push_subscriptions FOR DELETE
    TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

-- 12.6. Bật Realtime cho bảng `comments`
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.comments;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END IF;
END$$;
