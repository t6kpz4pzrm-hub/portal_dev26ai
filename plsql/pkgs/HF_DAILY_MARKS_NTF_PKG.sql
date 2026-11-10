CREATE OR REPLACE PACKAGE hf_daily_marks_ntf_pkg AS

    PROCEDURE enviar_reporte (p_customer in varchar, p_company in varchar2 , p_local_id in varchar2 , p_desc in varchar2, p_process_id in number);
    Procedure submit;
END hf_daily_marks_ntf_pkg;
/


CREATE OR REPLACE PACKAGE BODY          "HF_DAILY_MARKS_NTF_PKG" AS
--------------------------------------------------------
--  get_company_notification_email
--------------------------------------------------------
function get_company_notification_email(p_company in varchar2) return varchar2 
is
    l_company_code varchar2(12 char);
begin
    select email_notification 
    into l_company_code
    from sl_companies
    where company_code = p_company;
    return l_company_code;
exception
    when others
    then
        return null;
end get_company_notification_email;
--------------------------------------------------------
--  clob to blob
--------------------------------------------------------
function clob_to_blob(p_clob in clob) return blob is
    l_blob         blob;
    l_dest_offset  integer := 1;
    l_src_offset   integer := 1;
    l_lang_ctx     integer := dbms_lob.default_lang_ctx;
    l_warning      integer;
begin
    dbms_lob.createtemporary(l_blob, true);
    dbms_lob.converttoblob(
        dest_lob     => l_blob,
        src_clob     => p_clob,
        amount       => dbms_lob.lobmaxsize,
        dest_offset  => l_dest_offset,
        src_offset   => l_src_offset,
        blob_csid    => nls_charset_id('AL32UTF8'),
        lang_context => l_lang_ctx,
        warning      => l_warning
    );
    return l_blob;
end clob_to_blob;
--------------------------------------------------------
--  enviar_reporte
--------------------------------------------------------
PROCEDURE enviar_reporte (p_customer in varchar, p_company in varchar2 , p_local_id in varchar2 , p_desc in varchar2, p_process_id in number) IS
    l_csv               CLOB;
    l_blob              BLOB;
    l_email_id          NUMBER;
    l_active_report     varchar2(10);
    l_email             varchar2(100);
    l_db_name           varchar2(100);
    l_day               date:=current_date - 1;
    l_fecha             varchar2(30):=to_char(l_day,'RRRRMMDD');
    l_row               number:=0;  
    e_program_error     exception;
    l_program_error     varchar2(200):=null;
    l_program_name      varchar2(80 char):='HF_DAILY_MARKS_NTF_PKG.enviar_reporte';
BEGIN 
    sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'Start Program');   
    --print('> '||p_customer || ' / '||p_company || ' / '||p_local_id  || ' / '||l_fecha);

    --Proceso esta activo ?
    l_active_report:=nvl(sl_params_pkg.get(p_customer,'HF_DAILY_MARKS'),'N');
    if l_active_report not in ('Y','y','S','s','SI','si','Si')
    then
        l_program_error := 'Exit 01 - Parameter is Disabled or Null - '||l_active_report;
        raise e_program_error;
    end if;

    if to_number(p_local_id) <=0 or p_local_id is null
    then
        l_program_error := 'Exit 02 - Local ID is Wrong or 0 - '||p_local_id;
        raise e_program_error;
    end if;

    --l_email := 'jjvalenzuela@automatiza.cl';
    --sl_params_pkg.get(p_customer,'HF_DAILY_EMAIL');
    --l_email := 'mosorio@automatiza.cl';

    --if l_email is null
    --then
    --    l_email:=sl_params_pkg.get(p_customer,'HF_DAILY_EMAIL');
    --end if;
    
    l_email:=get_company_notification_email(p_company);
    
    if l_email is null
    then
        l_email:=sl_util_pkg.get_param('HF_DAILY_EMAIL');
    end if;
    
    if not REGEXP_LIKE (l_email,'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
    then
        l_program_error := 'Exit 03 - Email ID is Wrong or Null - '||l_email;
        raise e_program_error;
    end if;

    l_db_name := sl_params_pkg.get(p_customer,'DB_NAME');
    if l_db_name is null
    then
        l_program_error := 'Exit 04 - DBNAME String ID is Wrong or Null - '||l_db_name;
        raise e_program_error;
    end if;

    --print('> '||p_customer || ' / '||p_company || ' / '||p_local_id||' / '||l_email ||' / '||l_db_name);

    -- 1. Generar CSV con tu query
    l_csv := 'RUT;NOMBRE;PATERNO;MATERNO;MARCA;DIRECCION;SENTIDO;HASH;' || CHR(10);
    l_row := 1;

    sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'Validation Phase OK');   
    FOR r IN (
        select RUT
              ,CARDNO
              ,NOMBRE
              ,PATERNO
              ,MATERNO
              --,TO_CHAR(TO_DATE(FECHA_INGRESO,'YYYY-MM-DD"T"HH24:MI:SS".""ZZZZ"'),  'DD-MM-YYYY') FECHA_INGRESO
              --,TO_CHAR(TO_DATE(FECHA_EGRESO,'YYYY-MM-DD"T"HH24:MI:SS".""ZZZZ"'), 'DD-MM-YYYY') FECHA_EGRESO
              ,TO_CHAR(TO_DATE(MARCA,'YYYY-MM-DD"T"HH24:MI:SS".""ZZZZ"'), 'DY DD-MM-YYYY HH24:MI:SS') MARCA
              ,TO_CHAR(TO_DATE(MARCA,'YYYY-MM-DD"T"HH24:MI:SS".""ZZZZ"'), 'YYYY-MM-DD HH24:MI:SS') MARCA_AUX
              ,DIRECCION
              ,SENTIDO 
              ,HASH
        from HF_SUPERVISOR_API_PKG.get_consultaMarcas(                
                        p_cliente         => l_db_name,
                        p_empresa         => p_local_id,
                        p_rutJefe         => 'ALL',
                        p_rutTrab         => '*',
                        p_desde           => l_fecha,
                        p_hasta           => l_fecha,
                        p_turno           => '0',
                        p_dept            => '0',
                        p_ccosto          => '0',
                        p_area            => '0',
                        p_cargo           => '0',
                        p_local           => '0',
                        p_establecimiento => '0',
                        p_faena           => '0',
                        p_lugar           => '0',
                        p_solodirecta     => '0')
        ORDER BY MARCA_AUX ASC
    )
    LOOP
        --print(to_char(l_row));
        l_row:=l_row + 1;

        l_csv := l_csv      || 
              r.RUT         || ';'  ||
              r.NOMBRE      || ';'  ||
              r.PATERNO     || ';'  ||
              r.MATERNO     || ';'  ||
              r.MARCA       || ';'  ||
              r.DIRECCION   || ';'  ||
              r.SENTIDO     || ';'  ||
              r.HASH        || CHR(10);
    END LOOP;

    begin
        if l_row >=2
        then
            sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'Sending W/Data Email');  
            -- 2. Enviar correo con adjunto
            l_email_id :=APEX_MAIL.SEND(
              p_to        => l_email,
              p_bcc       => 'mosorio@automatiza.cl',
              p_from      => 'no-reply@mihumanforce.cl',
              p_subj      => 'Reporte Diario de Marcas : '||p_company || ' - '||to_char(l_day,'DY DD-MM-YYYY')|| CHR(10)||' - ['||p_local_id||']',
              p_body      => 'Reporte Diario de Marcas '|| CHR(10)
                ||' Fecha   : ' || to_char(l_day,'DY DD-MM-YYYY')|| CHR(10)
                ||' Empresa : '|| p_desc|| CHR(10)
                ||' Estado  : Reporte Adjunto'
            );
            sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'Sending Attachment');  
            
            -- 3. Adjuntar archivo
            l_blob := clob_to_blob(l_csv);            
            APEX_MAIL.ADD_ATTACHMENT(            
                p_mail_id    => l_email_id,            
                p_attachment => l_blob,            
                p_filename   => 'reporte_diario_marcas.csv',            
                p_mime_type  => 'text/csv; charset=UTF-8'            
            );   
        else
            sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'Sending No Data Email');           
            
            -- 2. Enviar correo con adjunto sin datos
            l_csv := l_csv || 'SIN DATOS;SIN DATOS;SIN DATOS;SIN DATOS;MARCA;SIN DATOS;SIN DATOS;SIN DATOS;' || CHR(10);

            l_email_id :=APEX_MAIL.SEND(
              p_to        => l_email,
              --p_bcc       => 'mosorio@automatiza.cl',
              p_from      => 'no-reply@mihumanforce.cl',
              p_subj      => 'Reporte Diario de Marcas : '||p_company || ' - '||to_char(l_day,'DY DD-MM-YYYY')|| CHR(10)||' - ['||p_local_id||']',
              p_body      => 'Reporte Diario de Marcas '|| CHR(10)
                ||' Fecha   : ' || to_char(l_day,'DY DD-MM-YYYY')|| CHR(10)
                ||' Empresa : '|| p_desc|| CHR(10)
                ||' Estado  : Sin Marcas'
            );   
            sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'Sending Attachment');  
            -- 3. Adjuntar archivo
            l_blob := clob_to_blob(l_csv);            
            APEX_MAIL.ADD_ATTACHMENT(            
                p_mail_id    => l_email_id,            
                p_attachment => l_blob,            
                p_filename   => 'reporte_diario_marcas.csv',            
                p_mime_type  => 'text/csv; charset=UTF-8'            
            );     
            
        end if; 

    exception
        when others
        then 
        l_program_error:=sqlerrm; 
        sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,l_program_error); 
    end;

    --Success
    insert into hf_daily_report_log
    ( customer_code,    company_code,   local_org_id          
    , report_date_from, report_date_to, marks_count           
    , execution_date,   marks_date,     active_report_flag    
    , report_email,     dbname,         mailid,         error_message)
    values 
    ( p_customer,       p_company,      p_local_id  
    , l_fecha,          l_fecha,        to_char(nvl(l_row,0))
    , current_date,     l_day,          'Y'
    , l_email,          l_db_name,      l_email_id,     l_program_error);
    commit;
    sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'--- Company End ---'); 
exception
    when e_program_error
    then
        sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,l_program_error); 
        sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'--------- x --------');         
        insert into hf_daily_report_log
        ( customer_code,    company_code,   local_org_id          
        , report_date_from, report_date_to, marks_count           
        , execution_date,   marks_date,     active_report_flag    
        , report_email,     dbname,         error_message)
        values 
        ( p_customer,       p_company,      p_local_id  
        , l_fecha,          l_fecha,        to_char(l_row)
        , current_date,     l_day,          'Y'
        , l_email,          l_db_name,      l_program_error);
        commit;
    when others
       then 
            --print('Error : '||p_customer || ' / '||p_company || ' / '||p_local_id  || ' / '||l_fecha);
            --print('Error : '||sqlerrm);            
            l_program_error:=sqlerrm;
            sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,l_program_error); 
            sl_util_pkg.traceg(p_process_id,p_company,l_program_name,null,null,'--------- x --------'); 
            insert into hf_daily_report_log
            ( customer_code,    company_code,   local_org_id          
            , report_date_from, report_date_to, marks_count           
            , execution_date,   marks_date,     active_report_flag    
            , report_email,     dbname,         error_message)
            values 
            ( p_customer,       p_company,      p_local_id  
            , l_fecha,          l_fecha,        to_char(l_row)
            , current_date,     l_day,          'Y'
            , l_email,          l_db_name,      'Error : '||l_program_error);
            commit;
END enviar_reporte;
--------------------------------------------------------
--  submit
--------------------------------------------------------
Procedure submit is

    cursor c_companies is
        select 
            co.customer_code , 
            co.company_code, 
            to_char(co.local_org_id) local_org_id, 
            co.company_name
        from sl_companies co, sl_customers cu
        where co.customer_code = cu.customer_code
            and co.local_org_id is not null
            and co.local_org_id !='0'
            and co.active_flag='Y'
            and cu.active_flag='Y'
        order by 1,2;
    l_active_report     varchar2(10);
    l_process_id        number;
    l_program_name      varchar2(80 char):='HF_DAILY_MARKS_NTF_PKG.submit';
    l_company           varchar2(12 char);
    l_customer          varchar2(12 char):='New';
    l_customerp         varchar2(12 char):='OLD';    
begin
    l_process_id := SL_LOG_ID_S.nextval;   
    sl_util_pkg.traceg(l_process_id,null,l_program_name,null,null,'Start Program');   
    l_customer:=null;
    for i in c_companies
    loop    
        l_customer:=i.customer_code;
        if l_customerp<>l_customer 
        then
            sl_util_pkg.traceg(l_process_id,l_company,l_program_name,null,null,'>>> Customer : '||l_customer);
            l_customerp:=l_customer;
        end if;
        l_active_report:= sl_params_pkg.get(i.customer_code,'HF_DAILY_MARKS');      
        if l_active_report in ('Y','y','S','s','SI','si','Si')
        then
            sl_util_pkg.traceg(l_process_id,l_company,l_program_name,null,null,'Running for '||i.company_code);
            enviar_reporte (p_customer => i.customer_code, p_company=> l_company, p_local_id => i.local_org_id, p_desc =>i.company_name, p_process_id=> l_process_id);
        else
            sl_util_pkg.traceg(l_process_id,i.company_code,l_program_name,null,null,'Skipping '||i.company_code);
            insert into hf_daily_report_log
            ( customer_code,                        company_code,   local_org_id          
            , report_date_from,                     report_date_to, marks_count           
            , execution_date,                       marks_date,     active_report_flag    
            , report_email
            , dbname)
            values 
            ( i.customer_code,                      i.company_code,                         i.local_org_id  
            , to_char(current_date-1,'RRRRMMDD'),   to_char(current_date-1,'RRRRMMDD'),     '0'
            , current_date,                         current_date-1,                         'N'
            , null
            , null);
            commit;
        end if;
    end loop;
    APEX_MAIL.PUSH_QUEUE;  
    sl_util_pkg.traceg(l_process_id,l_company,l_program_name,null,null,'Completed Sucessfully'); 
end submit;
END hf_daily_marks_ntf_pkg;
/
