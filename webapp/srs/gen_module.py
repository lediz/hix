#!/usr/bin/env python3
# gen_module.py - P4.3..P4.7: the remaining CRUD modules over the MySQL DAL.
#
# A local tool (not part of what ships); the generated .prg and .html files
# ARE what ships and are tracked.
#
# Unlike the abandoned first attempt, this does NOT write Harbour from a
# Python template: it transforms stock.prg, a file that is known to compile,
# by replacing the module name, the table, the column whitelists, the
# validation rules and the collect lines. Harbour's own braces are never
# written by Python, so the { => } / {{ }} collisions that made the template
# attempt fail do not exist here.

import re, os, sys, json

STOCK_CTRL = 'www/controllers/masters/stock.prg'
STOCK_VIEWS = 'www/views/masters/stock'
ROUTES = 'www/routes/web.json'

# name: (table, read cols, write cols [(col, type)], scope prefix, singular word)
MODULES = {
 # name: (table, read cols, write cols [(col, type)], scope prefix, singular word)
 'company':    ('company_company', ['name','description','website','contact'], [('name','s'),('description','s')], 'company', 'company'),
 'supplier':   ('part_supplierpart', ['part','supplier','SKU','manufacturer_part','link'], [('part','n'),('supplier','n'),('SKU','s')], 'supplier', 'supplier listing'),
 'bom':        ('part_bomitem', ['part','sub_part','quantity','raw_amount'], [('part','n'),('sub_part','n'),('quantity','n')], 'bom', 'BOM item'),
 'order':      ('order_salesorder', ['customer','reference','status','start_date'], [('customer','n'),('reference','s'),('status','n')], 'order', 'sales order'),
 'orderline':  ('order_salesorderlineitem', ['order','part','quantity','reference'], [('order','n'),('part','n'),('quantity','n')], 'order', 'order line'),
 'build':      ('build_build', ['part','parent','quantity','completed','creation_date'], [('part','n'),('quantity','n'),('creation_date','s')], 'build', 'build'),
 'testresult': ('stock_stockitemtestresult', ['stock_item','result','value','date'], [('stock_item','n'),('result','n'),('date','s')], 'test', 'test result'),
 'settings':   ('common_inventreesetting', ['key','value'], [('key','s'),('value','s')], 'prefs', 'setting'),
 'note':       ('common_note', ['title','description','content','updated_by'], [('title','s'),('content','s')], 'note', 'note'),
 'projectcode':('common_projectcode', ['code','description','active','responsible'], [('code','s'),('description','s')], 'project', 'project code'),
}

def rules(write):
    out = []
    for c, t in write:
        out.append('      "%s"    => "%s", ;' % (c, 'required|number|min:0' if t == 'n'
                                                   else 'required|string|max:100|field'))
    out[-1] = out[-1].replace(', ;', ' ;')
    return "\n".join(out)

def collect(write):
    q = chr(39)
    out = []
    for c, t in write:
        if t == 'n':
            out.append('   hData[ ' + chr(34) + c + chr(34) + ' ] := _NumOf( oVal:Get( ' + q + c + q + ' ) )')
        else:
            out.append('   hData[ ' + chr(34) + c + chr(34) + ' ] := AllTrim( oVal:Get( ' + q + c + q + ', ' + q + q + ' ) )')
    return chr(10).join(out) + chr(10)

def harbour_list(cols):
    return '{ ' + ', '.join('"%s"' % c for c in cols) + ' }'

def transform_ctrl(src, name, table, read, write, scope, sing, title):
    cls = title + 'Controllers'
    s = src
    # 1. the read whitelist: stock.prg writes it inline (possibly wrapped)
    s = re.sub(r'\{\s*"part",\s*"location",\s*"quantity",\s*"serial",\s*"barcode_hash"\s*\}',
               harbour_list(read).replace(' ', ' '), s, flags=re.S)
    # 2. the write whitelist
    s = re.sub(r'\{\s*"part",\s*"location",\s*"quantity",\s*"serial"\s*\}',
               harbour_list([c for c, _ in write]), s, flags=re.S)
    # 3. the validation rules block (twice: Store and Update)
    s = re.sub(r'UValidatePost\( \{ ;.*?\n   \} \)',
               lambda m: 'UValidatePost( { ;\n' + rules(write) + '\n   } )', s, flags=re.S)
    # 4. the collect block (contiguous hData assignments)
    s = re.sub(r'(   hData\[ "\w+" \]\s*:=.*\n)+',
               collect(write), s)
    # 5. names, table, paths, messages
    s = s.replace('StockControllers', cls)
    s = s.replace('CLASS Stock', 'CLASS ' + cls.split('Controllers')[0] + 'Controllers')
    s = s.replace('"stock_stockitem"', '"%s"' % table)
    s = s.replace("'stock.", "'%s." % name)
    s = s.replace('masters/stock/', 'masters/%s/' % name)
    s = s.replace("UFlash( 'stock' )", "UFlash( '%s' )" % name)
    s = s.replace('That stock item is not there.', 'That %s is not there.' % sing)
    s = s.replace("'Stock item '", "'%s '" % title)
    s = s.replace('// Stock - CRUD', '// %s - CRUD' % title)
    return s

def transform_view(src, name, read, write, title, sing):
    s = src
    s = s.replace('/stock/', '/%s/' % name)
    s = s.replace('Stock (Grid)', '%s (Grid)' % title)
    s = s.replace('Stock item #', '%s #' % title)
    s = s.replace('That stock item is not there.', 'That %s is not there.' % sing)
    s = s.replace('{{ if( cMode == \'create\', \'Create\', \'Edit\' ) }} stock item',
                  "{{ if( cMode == 'create', 'Create', 'Edit' ) }} %s" % sing)
    s = s.replace('Deleting stock item', 'Deleting %s' % sing)
    # grid cells and headers
    s = re.sub(r'<th>part</th><th>location</th><th>quantity</th><th>serial</th>',
               ''.join('<th>%s</th>' % c for c in read), s)
    s = re.sub(r'      <td>\{\{ HB_HGetDef\( hRow, \'part\', \'\' \) \}\}</td>\n'
               r'      <td>\{\{ HB_HGetDef\( hRow, \'location\', \'\' \) \}\}</td>\n'
               r'      <td>\{\{ HB_HGetDef\( hRow, \'quantity\', \'\' \) \}\}</td>\n'
               r'      <td>\{\{ HB_HGetDef\( hRow, \'serial\', \'\' \) \}\}</td>',
               ''.join('      <td>{{ HB_HGetDef( hRow, \'%s\', \'\' ) }}</td>\n' % c for c in read), s)
    # show list
    s = re.sub(r'  <dt>part</dt>.*?<dt>barcode</dt><dd>[^<]*\{\{ HB_HGetDef\( hRow, \'barcode_hash\', \'\' \) \}\}[^<]*</dd>\n',
               ''.join('  <dt>%s</dt><dd>{{ HB_HGetDef( hRow, \'%s\', \'\' ) }}</dd>\n' % (c, c) for c in read), s, flags=re.S)
    # edit inputs
    s = re.sub(r'<input type="text" name="part".*?<input type="text" name="serial"[^>]*>\n',
               ''.join('<input type="text" name="%s" value="{{ HB_HGetDef( hRow, \'%s\', \'\' ) }}">\n' % (c, c)
                       for c, _ in write), s, flags=re.S)
    return s

def routes(name, scope):
    p = name
    spec = [
      (p+'.grid',            '/'+p+'/grid',                        'grid',           'GET',  'MyAppAuthRole',     scope+':search'),
      (p+'.search',          '/'+p+'/search',                      'search',         'GET',  'MyAppAuthRole',     scope+':search'),
      (p+'.show',            '/'+p+'/:id([0-9]+)',                 'show',           'GET',  'MyAppAuthRole',     scope+':show'),
      (p+'.create',          '/'+p+'/create',                      'create',         'GET',  'MyAppAuthRole',     scope+':create'),
      (p+'.edit',            '/'+p+'/:id([0-9]+)/edit',            'edit',           'GET',  'MyAppAuthRole',     scope+':edit'),
      (p+'.store',           '/'+p+'/store',                       'store',          'POST', 'MyAppAuthRoleEdit', scope+':create'),
      (p+'.update',          '/'+p+'/:id([0-9]+)/update',          'update',         'POST', 'MyAppAuthRoleEdit', scope+':edit'),
      (p+'.delete_confirm',  '/'+p+'/:id([0-9]+)/delete_confirm',  'delete_confirm', 'GET',  'MyAppAuthRoleEdit', scope+':delete'),
      (p+'.delete',          '/'+p+'/:id([0-9]+)/delete',          'delete_action',  'POST', 'MyAppAuthRoleEdit', scope+':delete'),
    ]
    lines = open(ROUTES).read().split('\n')
    anchor = next(i for i, l in enumerate(lines) if 'sys.fk_check' in l)
    add = ['  { "name": "%s", "url": "%s", "action": "controllers/masters/%s@%s.prg", "method": "%s", "middleware": "%s", "scope": "%s" },'
           % (n, u, a, p, m, mw, sc) for (n, u, a, m, mw, sc) in spec]
    lines[anchor+1:anchor+1] = add
    open(ROUTES, 'w').write('\n'.join(lines))

if __name__ == '__main__':
    os.chdir('..')
    args = sys.argv[1:] if len(sys.argv) > 1 else []
    if args[:1] == ['--list']:
        print(' '.join(MODULES)); raise SystemExit
    names = list(MODULES) if args[:1] == ['--all'] else args
    base_ctrl = open(STOCK_CTRL).read()
    base_views = {fn: open('%s/%s' % (STOCK_VIEWS, fn)).read()
                  for fn in ('grid.html','show.html','edit.html','delete.html')}
    for n in names:
        table, read, write, scope, sing = MODULES[n]
        title = n[0].upper() + n[1:]
        open('www/controllers/masters/%s.prg' % n, 'w').write(
            transform_ctrl(base_ctrl, n, table, read, write, scope, sing, title))
        d = 'www/views/masters/%s' % n
        os.makedirs(d, exist_ok=True)
        for fn, body in base_views.items():
            open('%s/%s' % (d, fn), 'w').write(
                transform_view(body, n, read, write, title, sing))
        routes(n, scope)
        print('generated', n)
