"use client";

import { useWorkspacePaths } from "@multica/core/paths";
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@multica/ui/components/ui/sidebar";
import { AppLink } from "../navigation";
import { useT } from "../i18n";
import { AREAS, AreaDot } from "../empresa/shared";
import { routeIconForPath } from "./route-icon-components";

const NAV_ITEM_CLASS_NAME =
  "text-muted-foreground hover:not-data-active:bg-sidebar-accent/70 data-active:bg-sidebar-accent data-active:text-sidebar-accent-foreground";

/**
 * TLS "Empresa" group: company overview plus the six business areas in
 * presentation order. Area names are business data, shown as-is; the dot is
 * the area accent and always sits next to its name.
 */
export function EmpresaNavGroup({ pathname }: { pathname: string }) {
  const { t } = useT("layout");
  const p = useWorkspacePaths();
  const overview = p.empresa();
  const Icon = routeIconForPath(overview);
  return (
    <SidebarGroup>
      <SidebarGroupLabel>{t(($) => $.sidebar.empresa_group)}</SidebarGroupLabel>
      <SidebarGroupContent>
        <SidebarMenu className="gap-0.5">
          <SidebarMenuItem>
            <SidebarMenuButton isActive={pathname === overview} render={<AppLink href={overview} />} className={NAV_ITEM_CLASS_NAME}>
              <Icon />
              <span>{t(($) => $.nav.empresa)}</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          {AREAS.map((area) => {
            const href = p.empresaArea(area.code);
            return (
              <SidebarMenuItem key={area.code}>
                <SidebarMenuButton
                  isActive={pathname === href || pathname.startsWith(`${href}/`)}
                  render={<AppLink href={href} />}
                  className={NAV_ITEM_CLASS_NAME}
                >
                  <span className="flex size-4 items-center justify-center">
                    <AreaDot area={area.code} />
                  </span>
                  <span>{area.name}</span>
                </SidebarMenuButton>
              </SidebarMenuItem>
            );
          })}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  );
}
